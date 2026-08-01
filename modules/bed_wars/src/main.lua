--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy BedWarsModule.java. store.yml isn't registered - bed_wars' shop currency is
-- resource items, not a store category (no legacy StoreAPI usage to port here).
local gameManager = require("game_manager")
local listener = require("listener")
local setup = require("setup")
local voteService = require("support.vote_service")
local specialItemsService = require("support.special_items_service")

local M = {}

listener.register()
setup.register()
specialItemsService.register()

function M.onLoad()
  ba.stats.define("wins", ba.config.translation(nil, "stats.labels.wins"), ba.config.translation(nil, "stats.descriptions.wins"))
  ba.stats.define("games_played", ba.config.translation(nil, "stats.labels.games_played"), ba.config.translation(nil, "stats.descriptions.games_played"))
  ba.stats.define("kills", ba.config.translation(nil, "stats.labels.kills"), ba.config.translation(nil, "stats.descriptions.kills"))
  ba.stats.define("deaths", ba.config.translation(nil, "stats.labels.deaths"), ba.config.translation(nil, "stats.descriptions.deaths"))
  ba.stats.define("beds_broken", ba.config.translation(nil, "stats.labels.beds_broken"), ba.config.translation(nil, "stats.descriptions.beds_broken"))
  ba.stats.define("final_kills", ba.config.translation(nil, "stats.labels.final_kills"), ba.config.translation(nil, "stats.descriptions.final_kills"))

  ba.achievements.register("achievements.yml")

  ba.vote.register(
    ba.config.getString("menus.vote.item"),
    ba.config.translation(nil, "vote_menu.name"),
    ba.config.translationList(nil, "vote_menu.lore")
  )

  voteService.registerWaitingItem()
  voteService.registerClickHandler()

  -- Single dispatcher for vote/shop/upgrade payloads, mirroring legacy's own handleMenuAction.
  ba.menu.onAction(gameManager.handleMenuAction)

  -- Mirrors legacy's BedWarsMenuAPI registration under both the module id and a literal "bed" alias.
  ba.menu.onOpenById(voteService.handleMenuIdOpen)
  ba.menu.registerMenuIdAlias("bed")
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

function M.allowJoinInProgress()
  return true
end

function M.onGameStart(session)
  gameManager.beginPlaying(session)
end

function M.onEnd(session, result)
  gameManager.finishGame(session)
end

-- Mirrors legacy BedWarsGame.shutdown(): defensive cleanup only, no winner/stats. Menu/item handler
-- unregistration isn't ported (no equivalent teardown hook exists in this Lua layer).
function M.onDisable()
  for _, session in ipairs(ba.session.all()) do
    gameManager.handleDisableCleanup(session)
  end
end

function M.getCustomPlaceholders(session, handle)
  return gameManager.getCustomPlaceholders(session, handle)
end

return M

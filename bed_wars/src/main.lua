-- Mirrors legacy BedWarsModule.java. "store.yml" and the Bedrock-menu yml files
-- (menus/bedrock/*.yml) legacy registers in registerConfigs() are not ported - StoreAPI is
-- entirely unbound in this project's Lua layer (BedWarsStoreService.registerStoreItems is a no-op
-- gap already documented for every prior StoreAPI-using module) and the Bedrock menu path is
-- already documented as unreachable from a universal module (see docs/BAMODULE_STATUS.md).
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

  -- Legacy's registerMenuActions routes every "MODULE;bed_wars;<payload>" click through a single
  -- BedWarsGame.handleMenuAction dispatcher (vote/shop/upgrade payloads alike) - gameManager mirrors
  -- that single entry point rather than splitting per-subsystem the way capture_the_wool's simpler
  -- vote-only menu did.
  ba.menu.onAction(gameManager.handleMenuAction)
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

-- Legacy onDisable() re-cleans every still-active arena and unregisters menu/item handlers - not
-- ported, same documented gap as every other converted module's M.onDisable().
function M.onDisable()
end

function M.getCustomPlaceholders(session, handle)
  return gameManager.getCustomPlaceholders(session, handle)
end

return M

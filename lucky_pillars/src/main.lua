-- Mirrors legacy LuckyPillarsModule.java. requiresSpawnCapacityValidation isn't defined here -
-- legacy never overrides it either, so it keeps the framework default (true).
local gameManager = require("game_manager")
local listener = require("listener")
local setup = require("setup")
local voteService = require("support.vote_service")

local M = {}

listener.register()
setup.register()

function M.onLoad()
  ba.stats.define("wins", ba.config.translation(nil, "stats.labels.wins"), ba.config.translation(nil, "stats.descriptions.wins"))
  ba.stats.define("games_played", ba.config.translation(nil, "stats.labels.games_played"), ba.config.translation(nil, "stats.descriptions.games_played"))
  ba.stats.define("kills", ba.config.translation(nil, "stats.labels.kills"), ba.config.translation(nil, "stats.descriptions.kills"))

  ba.achievements.register("achievements.yml")

  ba.vote.register(
    ba.config.getString("menus.vote.item"),
    ba.config.translation(nil, "vote_menu.name"),
    ba.config.translationList(nil, "vote_menu.lore")
  )

  voteService.registerWaitingItem()
  voteService.registerClickHandler()

  -- Mirrors LuckyPillarsModule's own voteActionHandler lambda - parses the payload
  -- MenuActionExecutor already stripped "MODULE;lucky_pillars;" from ("menu modifiers" /
  -- "vote modifier <id>") back into an args array.
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

-- Legacy shutdown() defensively re-cleans every still-active arena's world/players/cages if the
-- module gets disabled mid-match. Not ported - same documented gap as every other converted
-- module's M.onDisable(), see docs/BAMODULE_STATUS.md.
function M.onDisable()
end

function M.getCustomPlaceholders(session, handle)
  return gameManager.getCustomPlaceholders(session, handle)
end

return M

-- Mirrors legacy SkyWarsModule.java. requiresSpawnCapacityValidation isn't defined here - legacy
-- never overrides it either, so it keeps the framework default (true). StoreAPI-driven kit/cage
-- registration calls aren't ported - see support/loadout_service.lua's own doc comment.
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
  ba.stats.define("chests_looted", ba.config.translation(nil, "stats.labels.chests_looted"), ba.config.translation(nil, "stats.descriptions.chests_looted"))
  -- storm_damage_taken - registered but never incremented anywhere, matching legacy's own
  -- StormService (its constructor accepts but discards a StatsAPI param); confirmed dead stat.
  ba.stats.define("storm_damage_taken", ba.config.translation(nil, "stats.labels.storm_damage_taken"), ba.config.translation(nil, "stats.descriptions.storm_damage_taken"))

  ba.achievements.register("achievements.yml")

  ba.vote.register(
    ba.config.getString("menus.vote.item"),
    ba.config.translation(nil, "vote_menu.name"),
    ba.config.translationList(nil, "vote_menu.lore")
  )

  voteService.registerWaitingItem()
  voteService.registerClickHandler()

  -- Mirrors SkyWarsModule's own voteActionHandler lambda - parses the payload
  -- MenuActionExecutor already stripped "MODULE;skywars;" from ("menu chests" /
  -- "vote chests overpowered") back into an args array.
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

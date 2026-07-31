-- Mirrors legacy BuildBattleModule.java. requiresSpawnCapacityValidation isn't defined here -
-- legacy never overrides it either, so it keeps the framework default (true). StoreAPI-driven
-- registration calls aren't ported - StoreAPI is entirely unbound in this project's Lua layer.
local gameManager = require("game_manager")
local listener = require("listener")
local setup = require("setup")
local voteService = require("support.vote_service")
local plotService = require("support.plot_service")
local optionsService = require("support.options_service")
local bannerService = require("support.banner_service")
local particleService = require("support.particle_service")
local headsService = require("support.heads_service")

local M = {}

listener.register()
setup.register()
optionsService.wire(bannerService, particleService, headsService)

function M.onLoad()
  ba.stats.define("wins", ba.config.translation(nil, "stats.labels.wins"), ba.config.translation(nil, "stats.descriptions.wins"))
  ba.stats.define("games_played", ba.config.translation(nil, "stats.labels.games_played"), ba.config.translation(nil, "stats.descriptions.games_played"))
  ba.stats.define("points_total", ba.config.translation(nil, "stats.labels.points_total"), ba.config.translation(nil, "stats.descriptions.points_total"))
  ba.stats.define("points_highest", ba.config.translation(nil, "stats.labels.points_highest"), ba.config.translation(nil, "stats.descriptions.points_highest"))

  ba.achievements.register("achievements.yml")

  ba.vote.register(
    ba.config.getString("menus.vote.item"),
    ba.config.translation(nil, "vote_menu.name"),
    ba.config.translationList(nil, "vote_menu.lore")
  )

  voteService.registerWaitingItem()
  voteService.registerClickHandler()

  -- Mirrors BuildBattleModule's own module action handler - OptionsService gets first refusal
  -- (matching legacy: "if (finalOptionsService != null && finalOptionsService.handleModuleAction(...))
  -- return true"), then falls back to the vote command, matching legacy's own
  -- "options ..." vs "vote ..." / "menu ..." routing exactly.
  ba.menu.onAction(function(playerHandle, payload)
    if not payload or payload == "" then
      return false
    end
    local args = {}
    for word in payload:gmatch("%S+") do
      args[#args + 1] = word
    end

    if args[1] and args[1]:lower() == "options" then
      local rest = {}
      for i = 2, #args do
        rest[#rest + 1] = args[i]
      end
      local session = ba.session.forPlayer(playerHandle)
      if session then
        return optionsService.handleModuleAction(session, playerHandle, rest, plotService)
      end
      return false
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

-- Legacy shutdown() defensively re-cleans every still-active arena's world/players on module
-- disable. Not ported - same documented gap as every other converted module's M.onDisable(), see
-- docs/BAMODULE_STATUS.md.
function M.onDisable()
end

function M.getCustomPlaceholders(session, handle)
  return gameManager.getCustomPlaceholders(session, handle)
end

return M

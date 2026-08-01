-- Mirrors legacy RunFromTheBeastModule.java. requiresSpawnCapacityValidation isn't defined here -
-- legacy never overrides it either, so it keeps the framework default (true). StoreAPI-driven
-- registration calls aren't ported - StoreAPI is entirely unbound in this project's Lua layer.
local gameManager = require("game_manager")
local listener = require("listener")
local setup = require("setup")
local armoryService = require("support.armory_service")

local M = {}

listener.register()
setup.register()

function M.onLoad()
  -- Descriptions are hardcoded English here, not translation keys - matching legacy
  -- RunFromTheBeastStatsService.registerStats' own literal, never-localized StatDefinition text
  -- exactly (this module's language files only carry stats.labels.*, no stats.descriptions.*).
  ba.stats.define("games_played", ba.config.translation(nil, "stats.labels.games_played"), "Run From The Beast games played")
  ba.stats.define("runner_wins", ba.config.translation(nil, "stats.labels.runner_wins"), "Wins achieved as a runner")
  ba.stats.define("beast_wins", ba.config.translation(nil, "stats.labels.beast_wins"), "Wins achieved as the beast")
  ba.stats.define("beast_roles", ba.config.translation(nil, "stats.labels.beast_roles"), "Times selected as the beast")
  ba.stats.define("beast_kills", ba.config.translation(nil, "stats.labels.beast_kills"), "Runners killed while playing as the beast")
  ba.stats.define("runner_kills", ba.config.translation(nil, "stats.labels.runner_kills"), "Beasts slain while playing as a runner")

  ba.achievements.register("achievements.yml")

  ba.vote.register(
    ba.config.getString("menus.vote.item"),
    ba.config.translation(nil, "vote_menu.name"),
    ba.config.translationList(nil, "vote_menu.lore")
  )

  -- Mirrors RunFromTheBeastModule's own module action handler - only the armory's own
  -- "armory_take <material> <amount>" click action is real here (see armory_service.lua's own
  -- doc comment for why it's click-to-take rather than a real lootable inventory).
  ba.menu.onAction(function(playerHandle, payload)
    if not payload or payload == "" then
      return false
    end
    local args = {}
    for word in payload:gmatch("%S+") do
      args[#args + 1] = word
    end

    if args[1] == "armory_take" and args[2] and args[3] then
      local session = ba.session.forPlayer(playerHandle)
      if session then
        armoryService.takeItem(session, playerHandle, args[2], tonumber(args[3]) or 1)
        return true
      end
    end
    return false
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
  return true
end

function M.onGameStart(session)
  gameManager.beginPlaying(session)
end

function M.onEnd(session, result)
  gameManager.onEnd(session)
end

-- Legacy shutdown() defensively re-cleans every still-active arena's world/players/cage/disguise
-- if the module gets disabled mid-match. Not ported - same documented gap as every other converted
-- module's M.onDisable(), see docs/BAMODULE_STATUS.md.
function M.onDisable()
end

function M.getCustomPlaceholders(session, handle)
  return gameManager.getCustomPlaceholders(session, handle)
end

return M

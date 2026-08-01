--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local gameManager = require("game_manager")
local listener = require("listener")
local setup = require("setup")
local armoryService = require("support.armory_service")
local storeService = require("support.store_service")

local M = {}

listener.register()
setup.register()

function M.onLoad()
  -- Descriptions are hardcoded English, matching legacy's own literal, never-localized text.
  ba.stats.define("games_played", ba.config.translation(nil, "stats.labels.games_played"), "Run From The Beast games played")
  ba.stats.define("runner_wins", ba.config.translation(nil, "stats.labels.runner_wins"), "Wins achieved as a runner")
  ba.stats.define("beast_wins", ba.config.translation(nil, "stats.labels.beast_wins"), "Wins achieved as the beast")
  ba.stats.define("beast_roles", ba.config.translation(nil, "stats.labels.beast_roles"), "Times selected as the beast")
  ba.stats.define("beast_kills", ba.config.translation(nil, "stats.labels.beast_kills"), "Runners killed while playing as the beast")
  ba.stats.define("runner_kills", ba.config.translation(nil, "stats.labels.runner_kills"), "Beasts slain while playing as a runner")

  ba.achievements.register("achievements.yml")

  storeService.registerStoreItems()

  ba.vote.register(
    ba.config.getString("menus.vote.item"),
    ba.config.translation(nil, "vote_menu.name"),
    ba.config.translationList(nil, "vote_menu.lore")
  )

  -- Only the armory's "armory_take <material> <amount>" click action is real - see armory_service.lua.
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

-- Mirrors legacy RunFromTheBeastGameManager.onDisable(): defensive cleanup only, no winner/stats.
function M.onDisable()
  for _, session in ipairs(ba.session.all()) do
    gameManager.handleDisableCleanup(session)
  end
end

function M.getCustomPlaceholders(session, handle)
  return gameManager.getCustomPlaceholders(session, handle)
end

return M

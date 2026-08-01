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
local statsService = require("support.stats_service")

local M = {}

listener.register()
setup.register()

function M.onLoad()
  statsService.registerStats()

  ba.achievements.register("achievements.yml")

  ba.vote.register(
    ba.config.getString("menus.vote.item"),
    ba.config.translation(nil, "vote_menu.name"),
    ba.config.translationList(nil, "vote_menu.lore")
  )
end

function M.onStart(session)
  gameManager.handleStart(session)
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
  gameManager.handleGameStart(session)
end

function M.onEnd(session, result)
  gameManager.handleEnd(session)
end

-- Defensive plugin-shutdown cleanup only - no winner, no stats, mirrors legacy handleDisable().
function M.onDisable()
  for _, session in ipairs(ba.session.all()) do
    gameManager.handleDisable(session)
  end
end

function M.getCustomPlaceholders(session, handle)
  return gameManager.getCustomPlaceholders(session, handle)
end

return M

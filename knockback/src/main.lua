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
  return false
end

function M.onGameStart(session)
  gameManager.handleGameStart(session)
end

function M.onEnd(session, result)
  gameManager.handleEnd(session)
end

-- Legacy onDisable() only cancels tasks and clears its arena registry - nothing cosmetic to undo.
function M.onDisable()
  for _, session in ipairs(ba.session.all()) do
    session.scheduler.cancelArenaTasks()
  end
end

function M.getCustomPlaceholders(session, handle)
  return gameManager.getCustomPlaceholders(session, handle)
end

return M

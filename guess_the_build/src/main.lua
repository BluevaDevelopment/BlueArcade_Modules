-- Mirrors legacy GuessTheBuildModule.java.
local gameManager = require("game_manager")
local listener = require("listener")
local chatListener = require("chat_listener")
local setup = require("setup")
local themeService = require("support.theme_service")

local M = {}

listener.register()
chatListener.register()
setup.register()

function M.onLoad()
  ba.stats.define("wins", ba.config.translation(nil, "stats.labels.wins"), ba.config.translation(nil, "stats.descriptions.wins"))
  ba.stats.define("games_played", ba.config.translation(nil, "stats.labels.games_played"), ba.config.translation(nil, "stats.descriptions.games_played"))
  ba.stats.define("points_total", ba.config.translation(nil, "stats.labels.points_total"), ba.config.translation(nil, "stats.descriptions.points_total"))
  ba.stats.define("points_highest", ba.config.translation(nil, "stats.labels.points_highest"), ba.config.translation(nil, "stats.descriptions.points_highest"))

  ba.achievements.register("achievements.yml")

  -- Mirrors GuessTheBuildModule.onLoad's own action-handler lambda: parses "theme <difficulty>"
  -- back off the payload MenuActionExecutor already stripped "MODULE;guess_the_build;" from.
  ba.menu.onAction(function(playerHandle, payload)
    if not payload or payload == "" then
      return false
    end
    local parts = {}
    for word in payload:gmatch("%S+") do
      parts[#parts + 1] = word
    end
    if #parts >= 2 and parts[1]:lower() == "theme" then
      return themeService.handleThemeAction(playerHandle, parts[2])
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
  return false
end

function M.requiresSpawnCapacityValidation()
  return false
end

function M.onGameStart(session)
  gameManager.beginPlaying(session)
end

function M.onEnd(session, result)
  gameManager.finishGame(session)
end

-- onDisable gets no session (unlike onEnd) - no live-session registry to iterate in Lua, so
-- legacy shutdown()'s mid-match cleanup isn't ported. Documented gap, not a silent drop.
function M.onDisable()
end

function M.getCustomPlaceholders(session, handle)
  return gameManager.getCustomPlaceholders(session)
end

return M

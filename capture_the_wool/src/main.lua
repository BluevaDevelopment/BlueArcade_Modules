-- Mirrors legacy CaptureTheWoolModule.java; requiresSpawnCapacityValidation stays framework default (true), matching legacy.
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
  -- chests_looted is never incremented in legacy either (dead instrumentation) - not a bug here.
  ba.stats.define("chests_looted", ba.config.translation(nil, "stats.labels.chests_looted"), ba.config.translation(nil, "stats.descriptions.chests_looted"))
  ba.stats.define("deaths", ba.config.translation(nil, "stats.labels.deaths"), ba.config.translation(nil, "stats.descriptions.deaths"))
  ba.stats.define("wools_stolen", ba.config.translation(nil, "stats.labels.wools_stolen"), ba.config.translation(nil, "stats.descriptions.wools_stolen"))
  ba.stats.define("wools_captured", ba.config.translation(nil, "stats.labels.wools_captured"), ba.config.translation(nil, "stats.descriptions.wools_captured"))

  ba.achievements.register("achievements.yml")

  ba.vote.register(
    ba.config.getString("menus.vote.item"),
    ba.config.translation(nil, "vote_menu.name"),
    ba.config.translationList(nil, "vote_menu.lore")
  )

  voteService.registerWaitingItem()
  voteService.registerClickHandler()

  -- payload is "menu <category>" / "vote <category> <option>" with the "MODULE;capture_the_wool;" prefix already stripped.
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

function M.allowJoinInProgress()
  return ba.config.getBoolean("join_in_progress.enabled", true)
end

function M.onPlayerJoinInProgress(session, handle)
  return gameManager.addLateJoiningPlayer(session, handle)
end

function M.onGameStart(session)
  gameManager.beginPlaying(session)
end

function M.onEnd(session, result)
  gameManager.finishGame(session)
end

-- Mirrors legacy CaptureTheWoolGame.shutdown(): defensive cleanup only, no winner/stats.
function M.onDisable()
  for _, session in ipairs(ba.session.all()) do
    gameManager.handleDisableCleanup(session)
  end
end

function M.getCustomPlaceholders(session, handle)
  return gameManager.getCustomPlaceholders(session, handle)
end

return M

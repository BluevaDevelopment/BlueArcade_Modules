-- Mirrors legacy CaptureTheWoolModule.java. requiresSpawnCapacityValidation isn't defined here -
-- legacy never overrides it either, so it keeps the framework default (true).
-- "chests_looted" is registered as a stat (matching legacy's own registerStats()) but never
-- actually incremented anywhere in the legacy source either - ArmoryService.openChestClone has no
-- stat call, confirmed by reading it in full - so the "Loot Runner" achievement tied to it is
-- legacy dead instrumentation, not a bug to fix here.
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

  -- Mirrors CaptureTheWoolModule's own registerMenuActions lambda - parses the payload
  -- MenuActionExecutor already stripped "MODULE;capture_the_wool;" from
  -- ("menu <category>" / "vote <category> <option>") back into an args array.
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

-- Legacy onDisable() calls game.shutdown() (defensive re-clean of every still-active arena's
-- world/players on module disable) and unregisters menu/item handlers - not ported, same
-- documented gap as every other converted module's M.onDisable(), see docs/BAMODULE_STATUS.md.
function M.onDisable()
end

function M.getCustomPlaceholders(session, handle)
  return gameManager.getCustomPlaceholders(session, handle)
end

return M

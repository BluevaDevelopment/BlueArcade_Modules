--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local game = require("game")
local listener = require("listener")
local setup = require("setup")
local stats = require("support.stats")

local M = {}

listener.register()
setup.register()

function M.onLoad()
  stats.register()

  ba.achievements.register("achievements.yml")

  ba.vote.register(
    ba.config.getString("menus.vote.item"),
    ba.config.translation(nil, "vote_menu.name"),
    ba.config.translationList(nil, "vote_menu.lore")
  )
end

function M.onStart(session)
  game.onStart(session)
end

function M.onCountdownTick(session, secondsLeft)
  game.onCountdownTick(session, secondsLeft)
end

function M.onCountdownFinish(session)
  game.onCountdownFinish(session)
end

function M.freezePlayersOnCountdown()
  return false
end

function M.onGameStart(session)
  game.onGameStart(session)
end

function M.onEnd(session, result)
  game.onEnd(session)
end

-- Defensive plugin-shutdown cleanup only - no winner, no stats, mirrors legacy onDisable().
function M.onDisable()
  for _, session in ipairs(ba.session.all()) do
    game.handleDisable(session)
  end
end

return M

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

return M

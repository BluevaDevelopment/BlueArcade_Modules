-- Mirrors legacy GuessTheBuildChatListener.java. Dispatches from `player_chat`
-- (AsyncPlayerChatEvent - the one non-main-thread event in the catalogue, see
-- UniversalEventListener.onAsyncPlayerChat's own doc for why that's now safe).
local gameManager = require("game_manager")
local hintService = require("support.hint_service")

local M = {}

function M.register()
  ba.events.on("player_chat", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end
    if session.state.phase ~= "BUILDING" then
      return
    end

    if e.player == session.state.currentBuilder then
      e:cancel()
      local msg = session.config.translation(e.player, "game.cant_talk_builder")
      if msg then
        session.messages.sendRaw(e.player, msg)
      end
      return
    end

    if hintService.hasGuessed(session, e.player) then
      e:cancel()
      local msg = session.config.translation(e.player, "game.cant_talk_guessed")
      if msg then
        session.messages.sendRaw(e.player, msg)
      end
      return
    end

    local message = e.message:match("^%s*(.-)%s*$")
    if message == "" then
      return
    end

    for _, synonym in ipairs(session.state.currentThemeSynonyms) do
      if synonym:lower() == message:lower() then
        e:cancel()
        local guesser = e.player
        session.scheduler.runLater("gtb_chat_guess_" .. guesser, function()
          gameManager.handleCorrectGuess(session, guesser)
        end, 0)
        break
      end
    end
  end)
end

return M

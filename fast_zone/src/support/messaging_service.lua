local M = {}

function M.sendDescription(session)
  for _, handle in ipairs(session.players()) do
    local description = session.config.translationList(handle, "description")
    for _, line in ipairs(description) do
      session.messages.sendRaw(handle, line)
    end
  end
end

function M.sendCountdownTick(session, secondsLeft)
  for _, handle in ipairs(session.players()) do
    session.sounds.play(handle, session.coreConfig.getSound("sounds.starting_game.countdown"))
    local title = string.gsub(session.coreConfig.language(handle, "titles.starting_game.title"), "{game_display_name}", "Fast Zone")
    title = string.gsub(title, "{time}", tostring(secondsLeft))
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.starting_game.subtitle"), "{game_display_name}", "Fast Zone")
    subtitle = string.gsub(subtitle, "{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.sendCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    local title = string.gsub(session.coreConfig.language(handle, "titles.game_started.title"), "{game_display_name}", "Fast Zone")
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.game_started.subtitle"), "{game_display_name}", "Fast Zone")
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 20)
    session.sounds.play(handle, session.coreConfig.getSound("sounds.starting_game.start"))
  end
end

function M.broadcastFinish(session, handle, position, message)
  if message == nil then return end

  message = string.gsub(message, "{player}", session.player.name(handle))
  message = string.gsub(message, "{position}", tostring(position))

  for _, target in ipairs(session.players()) do
    session.messages.sendRaw(target, message)
  end
end

function M.broadcastDeathMessage(session, handle, message)
  local isSpectator = false
  for _, spectator in ipairs(session.spectators()) do
    if spectator == handle then isSpectator = true end
  end
  if isSpectator then return end
  if message == nil then return end

  message = string.gsub(message, "{player}", session.player.name(handle))
  for _, target in ipairs(session.players()) do
    session.messages.sendRaw(target, message)
  end
end

return M

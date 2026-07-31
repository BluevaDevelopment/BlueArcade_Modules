local M = {}

function M.sendDescription(session, mode)
  for _, handle in ipairs(session.players()) do
    local description = session.config.translationList(handle, "description." .. mode)
    for _, line in ipairs(description) do
      session.messages.sendRaw(handle, line)
    end
  end
end

function M.sendCountdownTick(session, secondsLeft)
  for _, handle in ipairs(session.players()) do
    session.sounds.play(handle, session.coreConfig.getSound("sounds.starting_game.countdown"))
    local title = string.gsub(session.coreConfig.language(handle, "titles.starting_game.title"), "{game_display_name}", "Red Alert")
    title = string.gsub(title, "{time}", tostring(secondsLeft))
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.starting_game.subtitle"), "{game_display_name}", "Red Alert")
    subtitle = string.gsub(subtitle, "{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.sendCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    local title = string.gsub(session.coreConfig.language(handle, "titles.game_started.title"), "{game_display_name}", "Red Alert")
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.game_started.subtitle"), "{game_display_name}", "Red Alert")
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 20)
    session.sounds.play(handle, session.coreConfig.getSound("sounds.starting_game.start"))
  end
end

-- A second, separate title at game start - no sound, different timing (0/20/10) - sent on top of
-- (not instead of) sendCountdownFinish's own title, matching `RedAlertGameManager.handleGameStart`
-- calling `sendStartTitle` as well as the countdown-finish hook already having fired it once.
function M.sendStartTitle(session)
  for _, handle in ipairs(session.players()) do
    local title = string.gsub(session.coreConfig.language(handle, "titles.game_started.title"), "{game_display_name}", "Red Alert")
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.game_started.subtitle"), "{game_display_name}", "Red Alert")
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 10)
  end
end

function M.sendDeathMessage(session, handle)
  for _, spectator in ipairs(session.spectators()) do
    if spectator == handle then return end
  end

  local messages = session.config.translationList(nil, "messages.deaths.generic")
  if #messages == 0 then return end
  local message = string.gsub(messages[math.random(#messages)], "{victim}", session.player.name(handle))

  for _, target in ipairs(session.players()) do
    session.messages.sendRaw(target, message)
  end
end

function M.getModeDisplayName(session, handle, mode)
  return session.config.translation(handle, "scoreboard.mode_labels." .. mode)
end

return M

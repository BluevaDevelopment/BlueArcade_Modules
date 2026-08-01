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
    local title = string.gsub(session.coreConfig.language(handle, "titles.starting_game.title"), "{game_display_name}", "Splegg")
    title = string.gsub(title, "{time}", tostring(secondsLeft))
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.starting_game.subtitle"), "{game_display_name}", "Splegg")
    subtitle = string.gsub(subtitle, "{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.sendCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    local title = string.gsub(session.coreConfig.language(handle, "titles.game_started.title"), "{game_display_name}", "Splegg")
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.game_started.subtitle"), "{game_display_name}", "Splegg")
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 20)
    session.sounds.play(handle, session.coreConfig.getSound("sounds.starting_game.start"))
  end
end

function M.sendActionBar(session, handle, timeLeft)
  local template = session.coreConfig.language(handle, "action_bar.in_game.global")
  if template == nil then return end

  local message = string.gsub(template, "{time}", string.format("%02d:%02d", math.floor(timeLeft / 60), timeLeft % 60))
  message = string.gsub(message, "{round}", tostring(session.currentRound))
  message = string.gsub(message, "{round_max}", tostring(session.maxRounds))
  session.messages.sendActionBar(handle, message)
end

local function randomMessage(session, handle, path)
  local messages = session.config.translationList(handle, path)
  if #messages == 0 then return nil end
  return messages[math.random(#messages)]
end

-- Unlike spleef's single broadcast, splegg rolls a fresh random/translated message per recipient.
function M.broadcastElimination(session, victim)
  local isSpectator = false
  for _, spectator in ipairs(session.spectators()) do
    if spectator == victim then isSpectator = true end
  end
  if isSpectator then return end

  for _, handle in ipairs(session.players()) do
    local message = randomMessage(session, handle, "messages.deaths.generic")
    if message ~= nil then
      message = string.gsub(message, "{victim}", session.player.name(victim))
      session.messages.sendRaw(handle, message)
    end
  end
end

function M.playRespawnSound(session, handle)
  session.sounds.play(handle, session.coreConfig.getSound("sounds.in_game.respawn"))
end

return M

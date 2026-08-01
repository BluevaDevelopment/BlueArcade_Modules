--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local M = {}

function M.sendDescription(session, mode)
  local descriptionKey = "description." .. mode
  for _, handle in ipairs(session.players()) do
    local description = session.config.translationList(handle, descriptionKey)
    if #description == 0 then
      description = session.config.translationList(handle, "description")
    end
    for _, line in ipairs(description) do
      session.messages.sendRaw(handle, line)
    end
  end
end

function M.sendCountdownTick(session, secondsLeft)
  for _, handle in ipairs(session.players()) do
    session.sounds.play(handle, session.coreConfig.getSound("sounds.starting_game.countdown"))
    local title = string.gsub(session.coreConfig.language(handle, "titles.starting_game.title"), "{game_display_name}", "Snowball Fight")
    title = string.gsub(title, "{time}", tostring(secondsLeft))
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.starting_game.subtitle"), "{game_display_name}", "Snowball Fight")
    subtitle = string.gsub(subtitle, "{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.sendCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    local title = string.gsub(session.coreConfig.language(handle, "titles.game_started.title"), "{game_display_name}", "Snowball Fight")
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.game_started.subtitle"), "{game_display_name}", "Snowball Fight")
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 20)
    session.sounds.play(handle, session.coreConfig.getSound("sounds.starting_game.start"))
  end
end

local function randomMessage(session, path)
  local messages = session.config.translationList(nil, path)
  if #messages == 0 then return nil end
  return messages[math.random(#messages)]
end

function M.broadcastDeathMessage(session, victim, killer)
  local isSpectator = false
  for _, spectator in ipairs(session.spectators()) do
    if spectator == victim then isSpectator = true end
  end
  if isSpectator then return end

  local path = "messages.deaths.generic"
  if killer ~= nil then path = "messages.deaths.killed_by_player" end
  local message = randomMessage(session, path)
  if message == nil then return end

  message = string.gsub(message, "{victim}", session.player.name(victim))
  message = string.gsub(message, "{killer}", killer ~= nil and session.player.name(killer) or "")

  for _, handle in ipairs(session.players()) do
    session.messages.sendRaw(handle, message)
  end
end

function M.sendDeathTitle(session, handle)
  session.titles.sendRaw(handle,
    session.config.translation(handle, "titles.you_died.title"),
    session.config.translation(handle, "titles.you_died.subtitle"),
    0, 80, 20)
end

function M.playRespawnSound(session, handle)
  session.sounds.play(handle, session.coreConfig.getSound("sounds.in_game.respawn"))
end

function M.playDeathSound(session, handle)
  session.sounds.play(handle, session.coreConfig.getSound("sounds.in_game.dead"))
end

return M

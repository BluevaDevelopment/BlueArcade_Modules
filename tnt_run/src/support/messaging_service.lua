--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

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
    local title = string.gsub(session.coreConfig.language(handle, "titles.starting_game.title"), "{game_display_name}", "TNT Run")
    title = string.gsub(title, "{time}", tostring(secondsLeft))
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.starting_game.subtitle"), "{game_display_name}", "TNT Run")
    subtitle = string.gsub(subtitle, "{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.sendCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    local title = string.gsub(session.coreConfig.language(handle, "titles.game_started.title"), "{game_display_name}", "TNT Run")
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.game_started.subtitle"), "{game_display_name}", "TNT Run")
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 20)
    session.sounds.play(handle, session.coreConfig.getSound("sounds.starting_game.start"))
  end
end

function M.sendStartTitle(session)
  for _, handle in ipairs(session.players()) do
    local title = string.gsub(session.coreConfig.language(handle, "titles.game_started.title"), "{game_display_name}", "TNT Run")
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.game_started.subtitle"), "{game_display_name}", "TNT Run")
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 10)
  end
end

local function isSpectator(session, handle)
  for _, spectator in ipairs(session.spectators()) do
    if spectator == handle then return true end
  end
  return false
end

local function randomMessage(session, path)
  local messages = session.config.translationList(nil, path)
  if #messages == 0 then return nil end
  return messages[math.random(#messages)]
end

function M.sendDeathMessage(session, victim)
  if isSpectator(session, victim) then return end

  local message = randomMessage(session, "messages.deaths.generic")
  if message == nil then return end

  message = string.gsub(message, "{victim}", session.player.name(victim))
  for _, target in ipairs(session.players()) do
    session.messages.sendRaw(target, message)
  end
end

function M.sendVictoryMessage(session, winner)
  local message = randomMessage(session, "messages.victory")
  if message == nil then return end

  message = string.gsub(message, "{winner}", session.player.name(winner))
  for _, target in ipairs(session.players()) do
    session.messages.sendRaw(target, message)
  end
end

function M.sendFloorRemovalWarning(session, floorIndex, secondsLeft)
  for _, handle in ipairs(session.players()) do
    local message = session.config.translation(handle, "messages.floor_removal_warning")
    if message ~= nil then
      message = string.gsub(message, "{floor}", tostring(floorIndex))
      message = string.gsub(message, "{time}", tostring(secondsLeft))
      session.messages.sendRaw(handle, message)
    end
  end
end

function M.sendFloorRemoved(session, floorIndex)
  for _, handle in ipairs(session.players()) do
    local message = session.config.translation(handle, "messages.floor_removed")
    if message ~= nil then
      session.messages.sendRaw(handle, string.gsub(message, "{floor}", tostring(floorIndex)))
    end
  end
end

return M

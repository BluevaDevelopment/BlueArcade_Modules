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
    local description = session.config.translationList(handle, "description.default")
    for _, line in ipairs(description) do
      session.messages.sendRaw(handle, line)
    end
  end
end

function M.sendCountdownTick(session, secondsLeft)
  for _, handle in ipairs(session.players()) do
    session.sounds.play(handle, session.coreConfig.getSound("sounds.starting_game.countdown"))
    local title = string.gsub(session.coreConfig.language(handle, "titles.starting_game.title"), "{game_display_name}", "Block Party")
    title = string.gsub(title, "{time}", tostring(secondsLeft))
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.starting_game.subtitle"), "{game_display_name}", "Block Party")
    subtitle = string.gsub(subtitle, "{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.sendCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    local title = string.gsub(session.coreConfig.language(handle, "titles.game_started.title"), "{game_display_name}", "Block Party")
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.game_started.subtitle"), "{game_display_name}", "Block Party")
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 20)
    session.sounds.play(handle, session.coreConfig.getSound("sounds.starting_game.start"))
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

function M.broadcastDeathMessage(session, victim)
  if isSpectator(session, victim) then return end

  local message = randomMessage(session, "messages.deaths.generic")
  if message == nil then return end

  message = string.gsub(message, "{victim}", session.player.name(victim))
  for _, handle in ipairs(session.players()) do
    session.messages.sendRaw(handle, message)
  end
end

function M.sendRoundStarting(session, round)
  for _, handle in ipairs(session.players()) do
    session.messages.sendRaw(handle, string.gsub(session.config.translation(handle, "messages.round.starting"), "{bp_round}", tostring(round)))
  end
end

function M.sendRoundReveal(session, targetMaterial)
  local blockName = M.formatMaterialName(targetMaterial)
  for _, handle in ipairs(session.players()) do
    session.messages.sendRaw(handle, string.gsub(session.config.translation(handle, "messages.round.reveal"), "{block}", blockName))
  end
end

function M.sendRoundCollapsing(session)
  for _, handle in ipairs(session.players()) do
    session.messages.sendRaw(handle, session.config.translation(handle, "messages.round.collapsing"))
  end
end

function M.sendPowerupCollected(session, collector, powerupPlainName)
  local message = string.gsub(session.config.translation(collector, "messages.powerups.collected"), "{player}", session.player.name(collector))
  message = string.gsub(message, "{powerup}", powerupPlainName)
  for _, handle in ipairs(session.players()) do
    session.messages.sendRaw(handle, message)
  end
end

function M.formatMaterialName(material)
  if material == nil then return "Unknown" end
  local name = material:lower():gsub("_", " ")
  return name:sub(1, 1):upper() .. name:sub(2)
end

return M

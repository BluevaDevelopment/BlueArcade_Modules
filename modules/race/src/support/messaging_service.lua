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
    local title = string.gsub(session.coreConfig.language(handle, "titles.starting_game.title"), "{game_display_name}", "Race")
    title = string.gsub(title, "{time}", tostring(secondsLeft))
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.starting_game.subtitle"), "{game_display_name}", "Race")
    subtitle = string.gsub(subtitle, "{time}", tostring(secondsLeft))
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 5)
  end
end

function M.sendCountdownFinish(session)
  for _, handle in ipairs(session.players()) do
    local title = string.gsub(session.coreConfig.language(handle, "titles.game_started.title"), "{game_display_name}", "Race")
    local subtitle = string.gsub(session.coreConfig.language(handle, "titles.game_started.subtitle"), "{game_display_name}", "Race")
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

local function randomMessage(session, path)
  local messages = session.config.translationList(nil, path)
  if #messages == 0 then return nil end
  return messages[math.random(#messages)]
end

function M.broadcastDeath(session, handle, deathBlock)
  local isSpectator = false
  for _, spectator in ipairs(session.spectators()) do
    if spectator == handle then isSpectator = true end
  end
  if isSpectator then return end

  local path = deathBlock and "messages.deaths.death_block" or "messages.deaths.void"
  local message = randomMessage(session, path)
  if message == nil then return end

  message = string.gsub(message, "{player}", session.player.name(handle))
  for _, target in ipairs(session.players()) do
    session.messages.sendRaw(target, message)
  end
end

function M.broadcastFinish(session, handle, position)
  local message = randomMessage(session, "messages.finish.crossed")
  if message == nil then return end

  message = string.gsub(message, "{player}", session.player.name(handle))
  message = string.gsub(message, "{position}", tostring(position))

  for _, target in ipairs(session.players()) do
    session.messages.sendRaw(target, message)
  end
end

function M.sendFinishTitles(session, handle, position)
  local title = session.config.translation(handle, "titles.finished.title")
  local subtitle = string.gsub(session.config.translation(handle, "titles.finished.subtitle"), "{position}", tostring(position))
  session.titles.sendRaw(handle, title, subtitle, 0, 80, 20)
  session.sounds.play(handle, session.coreConfig.getSound("sounds.in_game.classified"))
end

function M.playRespawnSound(session, handle)
  session.sounds.play(handle, session.coreConfig.getSound("sounds.in_game.respawn"))
end

function M.getDeathBlock(session)
  local name = session.dataAccess.getGameDataString("basic.death_block")
  if name == nil then return "BARRIER" end
  return string.upper(name)
end

function M.isInsideFinishLine(session, location)
  local finishMin = session.dataAccess.getGameLocation("game.finish_line.bounds.min")
  local finishMax = session.dataAccess.getGameLocation("game.finish_line.bounds.max")
  if finishMin == nil or finishMax == nil then return false end

  return location.x >= math.min(finishMin.x, finishMax.x) and location.x <= math.max(finishMin.x, finishMax.x)
      and location.y >= math.min(finishMin.y, finishMax.y) and location.y <= math.max(finishMin.y, finishMax.y)
      and location.z >= math.min(finishMin.z, finishMax.z) and location.z <= math.max(finishMin.z, finishMax.z)
end

return M

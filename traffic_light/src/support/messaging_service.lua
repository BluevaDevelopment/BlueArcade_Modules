local M = {}

function M.sendDescription(session)
  for _, handle in ipairs(session.players()) do
    local description = session.config.translationList(handle, "description")
    for _, line in ipairs(description) do
      session.messages.sendRaw(handle, line)
    end
  end
end

local function randomMessage(session, path)
  local messages = session.config.translationList(nil, path)
  if #messages == 0 then return nil end
  return messages[math.random(#messages)]
end

function M.sendPushbackWarning(session, handle)
  local warning = session.config.translation(handle, "messages.red_light.pushback_warning")
  if warning ~= nil and warning ~= "" then
    session.messages.sendRaw(handle, warning)
  end
end

function M.handleRedLightDeathMessage(session, handle)
  local message = randomMessage(session, "messages.deaths.red_light")
  if message == nil then return end

  message = string.gsub(message, "{player}", session.player.name(handle))
  for _, target in ipairs(session.players()) do
    session.messages.sendRaw(target, message)
  end
end

function M.handlePlayerDeath(session, handle, deathBlock)
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

return M

local M = {}

function M.sendDescription(session)
  for _, handle in ipairs(session.players()) do
    local description = session.config.translationList(handle, "description")
    for _, line in ipairs(description) do
      session.messages.sendRaw(handle, line)
    end
  end
end

local function isSpectator(session, handle)
  for _, spectator in ipairs(session.spectators()) do
    if spectator == handle then return true end
  end
  return false
end

function M.broadcastDeathMessage(session, victim)
  if isSpectator(session, victim) then return end

  local messages = session.config.translationList(nil, "messages.deaths.generic")
  if #messages == 0 then return end
  local message = messages[math.random(#messages)]

  message = string.gsub(message, "{victim}", session.player.name(victim))
  for _, handle in ipairs(session.players()) do
    session.messages.sendRaw(handle, message)
  end
end

return M

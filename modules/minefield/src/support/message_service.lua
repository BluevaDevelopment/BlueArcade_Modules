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

local function randomMessage(session, path)
  local messages = session.config.translationList(nil, path)
  if #messages == 0 then return nil end
  return messages[math.random(#messages)]
end

function M.broadcastDeathMessage(session, handle, deathBlock)
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

function M.getMineTriggeredMessage(session)
  return randomMessage(session, "messages.mines.triggered")
end

return M

--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local M = {}

local function getWinMode(session)
  local mode = session.dataAccess.getGameDataString("basic.win_mode")
  if mode == nil then return "last_standing" end
  mode = string.lower(mode)
  if mode ~= "last_standing" and mode ~= "most_kills" then return "last_standing" end
  return mode
end

function M.sendDescription(session)
  local descriptionKey = "description." .. getWinMode(session)
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

return M

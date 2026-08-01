--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local M = {}

local function splitColon(text)
  local parts = {}
  for part in string.gmatch(text, "[^:]+") do
    parts[#parts + 1] = part
  end
  return parts
end

function M.tickSupplies(session)
  local interval = session.config.getInt("items.timed_supplies.interval_ticks", 0)
  local supplies = session.config.getStringList("items.timed_supplies.items")

  if interval <= 0 or #supplies == 0 then return end

  session.state.supplyTicks = session.state.supplyTicks + 20
  if session.state.supplyTicks % interval ~= 0 then return end

  for _, handle in ipairs(session.players()) do
    if session.isPlaying(handle) then
      for _, itemString in ipairs(supplies) do
        local parts = splitColon(itemString)
        if #parts >= 2 then
          session.player.giveItem(handle, parts[1], tonumber(parts[2]), -1)
        end
      end
    end
  end
end

return M

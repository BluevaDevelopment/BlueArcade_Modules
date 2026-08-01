--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- applyRespawnEffects isn't ported - confirmed dead code in the legacy source (defined, never called).
local M = {}

function M.giveStartingItems(session, handle)
  for _, itemStr in ipairs(session.config.getStringList("items.starting_items")) do
    local parts = {}
    for part in itemStr:gmatch("[^:]+") do
      parts[#parts + 1] = part
    end
    if #parts >= 2 then
      local amount = tonumber(parts[2])
      local slot = parts[3] and tonumber(parts[3]) or -1
      if amount then
        session.player.giveItem(handle, parts[1], amount, slot)
      end
    end
  end
end

local function applyEffects(session, handle, path)
  for _, effectStr in ipairs(session.config.getStringList(path)) do
    local parts = {}
    for part in effectStr:gmatch("[^:]+") do
      parts[#parts + 1] = part
    end
    if #parts >= 3 then
      local duration = tonumber(parts[2])
      local amplifier = tonumber(parts[3])
      if duration and amplifier then
        session.player.addPotionEffect(handle, parts[1], duration, amplifier)
      end
    end
  end
end

function M.applyStartingEffects(session, handle)
  applyEffects(session, handle, "effects.starting_effects")
end

function M.restoreVitals(session, handle)
  session.player.setHealth(handle, session.player.maxHealth(handle))
  session.player.setFoodLevel(handle, 20)
  session.player.setSaturation(handle, 20.0)
end

function M.handleKillRegeneration(session, killerHandle)
  local healAmount = session.config.getDouble("combat.kill_regeneration.health", 6.0)
  if healAmount <= 0 then
    return
  end
  local newHealth = math.min(session.player.maxHealth(killerHandle), session.player.health(killerHandle) + healAmount)
  session.player.setHealth(killerHandle, newHealth)
end

return M

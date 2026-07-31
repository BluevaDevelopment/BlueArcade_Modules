local M = {}

local function splitColon(text)
  local parts = {}
  for part in string.gmatch(text, "[^:]+") do
    parts[#parts + 1] = part
  end
  return parts
end

function M.giveStartingItems(session, handle)
  local items = session.config.getStringList("items.starting_items")
  for _, itemString in ipairs(items) do
    local parts = splitColon(itemString)
    if #parts >= 2 then
      local slotNumber = -1
      if #parts >= 3 then slotNumber = tonumber(parts[3]) end
      session.player.giveItem(handle, parts[1], tonumber(parts[2]), slotNumber)
    end
  end
end

local function applyEffects(session, handle, path)
  local effects = session.config.getStringList(path)
  for _, effectString in ipairs(effects) do
    local parts = splitColon(effectString)
    if #parts >= 3 then
      session.player.addPotionEffect(handle, parts[1], tonumber(parts[2]), tonumber(parts[3]))
    end
  end
end

function M.applyStartingEffects(session, handle)
  applyEffects(session, handle, "effects.starting_effects")
end

function M.applyRespawnEffects(session, handle)
  applyEffects(session, handle, "effects.respawn_effects")
end

local function restoreHealthAndHunger(session, handle)
  session.player.setHealth(handle, session.player.maxHealth(handle))
  session.player.setFoodLevel(handle, 20)
  session.player.setSaturation(handle, 20.0)
end

function M.prepareForStart(session, handle)
  session.player.setGameMode(handle, "SURVIVAL")
  restoreHealthAndHunger(session, handle)
  M.giveStartingItems(session, handle)
  M.applyStartingEffects(session, handle)
  M.applyRespawnEffects(session, handle)
end

function M.prepareForRespawn(session, handle)
  session.player.setGameMode(handle, "SURVIVAL")
  restoreHealthAndHunger(session, handle)
  M.giveStartingItems(session, handle)
  M.applyRespawnEffects(session, handle)
end

return M

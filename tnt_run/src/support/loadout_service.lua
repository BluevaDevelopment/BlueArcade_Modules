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

-- respawn_effects/handleRespawnEffects: confirmed dead code via grep, not ported.
function M.applyStartingEffects(session, handle)
  applyEffects(session, handle, "effects.starting_effects")
end

return M

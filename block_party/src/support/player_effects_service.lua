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

-- giveTargetItem decorates a plain material stack with a display name via giveEnchantedItem's
-- name/lore parameters (no real enchant), matching ItemAPI.decorate's own cosmetic-only use here.
function M.giveTargetItem(session, handle, targetMaterial)
  if not session.config.getBoolean("gameplay.give_target_item", true) then return end
  if targetMaterial == nil or targetMaterial == "AIR" then return end

  local slot = session.config.getInt("gameplay.target_item_slot", 4)
  local name = session.config.translation(handle, "items.target_name")
  session.player.giveEnchantedItem(handle, targetMaterial, 1, slot, nil, nil, false, name, {})
end

function M.clearPlayerInventories(session)
  for _, handle in ipairs(session.alivePlayers()) do
    session.player.clearInventory(handle)
  end
end

return M

local M = {}

function M.giveItems(session, handle, path)
  for _, itemStr in ipairs(session.config.getStringList(path)) do
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

function M.applyStartingEffects(session, handle, path)
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

function M.applyBeastEquipment(session, beast)
  if not session.config.getBoolean("game.beast_equipment.enabled", true) then
    return
  end
  local pieces = {
    { path = "game.beast_equipment.helmet", slot = 39 },
    { path = "game.beast_equipment.chestplate", slot = 38 },
    { path = "game.beast_equipment.leggings", slot = 37 },
    { path = "game.beast_equipment.boots", slot = 36 },
    -- main_hand goes to hotbar slot 0 (not legacy's setItemInMainHand) - always empty and
    -- selected right after clearInventory, so the effective result is the same.
    { path = "game.beast_equipment.main_hand", slot = 0 },
  }
  for _, piece in ipairs(pieces) do
    local material = session.config.getString(piece.path)
    if material and material ~= "" and material:upper() ~= "AIR" then
      session.player.giveItem(beast, material, 1, piece.slot)
    end
  end
end

return M

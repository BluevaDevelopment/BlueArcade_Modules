-- Mirrors legacy ArmoryService.java: a real, ordinary (non-container-backed) inventory snapshot of
-- whatever chest/container block the player right-clicked - never linked back to the real
-- container, matching legacy's own `Bukkit.createInventory(null, ...)` clone. Returns false when
-- the targeted block isn't a real container at all (session.world.containerSizeAt returns nil),
-- letting the caller know not to cancel the interact event for a non-container block.
local M = {}

function M.openChestClone(session, handle, x, y, z)
  local size = session.world.containerSizeAt(x, y, z)
  if not size then
    return false
  end

  local menuSize = size
  if menuSize % 9 ~= 0 then
    menuSize = (math.floor(menuSize / 9) + 1) * 9
  end
  menuSize = math.max(9, math.min(54, menuSize))

  local contents = session.world.containerContentsAt(x, y, z) or {}
  local items = {}
  for i, entry in ipairs(contents) do
    if i > menuSize then break end
    items[#items + 1] = { slot = i - 1, material = entry.material, amount = entry.amount }
  end

  local title = session.config.getString("inventories.chest_clone_title") or "<dark_gray>Chest</dark_gray>"
  session.player.openClonedInventory(handle, title, menuSize, items)
  return true
end

return M

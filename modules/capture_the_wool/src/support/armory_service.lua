--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy ArmoryService.java, but uses session.menu.open (always click-cancelled) instead of legacy's raw
-- openInventory clone, which let players actually pull duplicate items out of the "preview" - a deliberate fix, not a byte-for-byte port. Only material/amount survive the clone, not full ItemMeta.
local M = {}

function M.openChestClone(session, handle, x, y, z)
  local contents = session.world.containerContentsAt(x, y, z)
  if not contents then
    return false
  end

  local containerSize = session.world.containerSizeAt(x, y, z) or 27
  local size = math.max(9, math.min(54, math.ceil(containerSize / 9) * 9))

  local items = {}
  for i, entry in ipairs(contents) do
    if i > size then
      break
    end
    items[#items + 1] = {
      slot = i - 1,
      material = entry.material,
      amount = entry.amount,
      name = " ",
      lore = {},
      actions = {},
    }
  end

  return session.menu.open(handle, "<dark_gray>Chest</dark_gray>", size, items, {})
end

return M

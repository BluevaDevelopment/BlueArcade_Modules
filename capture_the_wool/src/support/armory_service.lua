-- Mirrors legacy ArmoryService.java's "open a read-only clone of a right-clicked container" -
-- but built on session.menu.open (real MenuAPI item slots, always click-cancelled) instead of
-- legacy's raw player.openInventory(clone), which never cancelled clicks and so actually let a
-- player pull duplicate items out of the "preview". Reusing the menu binding is a deliberate,
-- documented behavior improvement (properly read-only), not a byte-for-byte port. Only
-- material/amount survive the clone, not exact ItemMeta (name/lore/enchants) - matches
-- WorldBinding.containerContentsAt's own documented scope.
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

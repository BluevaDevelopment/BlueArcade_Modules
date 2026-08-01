-- Mirrors legacy RunFromTheBeastArmoryService.java. Legacy opens a real, lootable Bukkit
-- Inventory (drag items straight into your own inventory) - this project's session.menu.open only
-- supports click-driven button menus (MenuAPI's real click dispatch, not free dragging), so each
-- armory item is click-to-take instead ("MODULE;run_from_the_beast;armory_take <index>" gives that
-- exact item to whoever clicks it) - a real interaction-model adaptation, not a read-only clone
-- like capture_the_wool's own ArmoryService (that one is deliberately look-but-don't-touch; this
-- one's whole point is gearing up, so the "take an item" outcome is preserved even though the
-- click-vs-drag mechanic differs).
local M = {}

local function parseItemSpec(spec)
  local parts = {}
  for part in spec:gmatch("[^:]+") do
    parts[#parts + 1] = part
  end
  if #parts < 1 then
    return nil
  end
  return { material = parts[1]:upper(), amount = tonumber(parts[2]) or 1 }
end

function M.openArmory(session, handle, x, y, z)
  local allowBeast = session.config.getBoolean("game.allow_beast_loot", true)
  if not allowBeast and session.state.beastId == handle then
    session.messages.sendRaw(handle, session.config.translation(handle, "messages.armory_beast_blocked"))
    return
  end

  local items = {}
  if x then
    local contents = session.world.containerContentsAt(x, y, z)
    if contents then
      for _, entry in ipairs(contents) do
        items[#items + 1] = entry
      end
    end
  end

  if #items == 0 then
    for _, spec in ipairs(session.config.getStringList("armory.fallback_items")) do
      local item = parseItemSpec(spec)
      if item then
        items[#items + 1] = item
      end
    end
  end

  local menuSize = 54
  if x then
    local containerSize = session.world.containerSizeAt(x, y, z)
    if containerSize then
      if containerSize % 9 ~= 0 then
        containerSize = (math.floor(containerSize / 9) + 1) * 9
      end
      menuSize = math.max(9, math.min(54, containerSize))
    end
  end

  local menuItems = {}
  for i, item in ipairs(items) do
    if i - 1 >= menuSize then
      break
    end
    menuItems[#menuItems + 1] = {
      slot = i - 1,
      material = item.material,
      amount = item.amount,
      lore = { "<green>Click to take</green>" },
      actions = { "MODULE;run_from_the_beast;armory_take " .. item.material .. " " .. item.amount },
    }
  end

  local title = session.config.translation(handle, "menus.armory.title") or "Armory"
  session.menu.open(handle, title, menuSize, menuItems, {})
end

function M.takeItem(session, handle, material, amount)
  session.player.giveItem(handle, material, amount, -1)
end

return M

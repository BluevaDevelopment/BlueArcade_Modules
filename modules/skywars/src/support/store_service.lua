--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy SkyWarsStoreService's registration (kits.yml/cage.yml-sourced items, everything else static).
local M = {}

local function readItemsFrom(file, orderPath, base, fallbackIcon)
  local items = {}
  for _, itemId in ipairs(ba.config.getStringListFrom(file, orderPath)) do
    local itemPath = base .. "." .. itemId
    items[#items + 1] = {
      id = itemId,
      displayName = ba.config.getStringFrom(file, itemPath .. ".name", itemId),
      icon = ba.config.getStringFrom(file, itemPath .. ".icon") or fallbackIcon,
      description = ba.config.getStringListFrom(file, itemPath .. ".description"),
      price = ba.config.getIntFrom(file, itemPath .. ".price", 0),
      enabled = ba.config.getBooleanFrom(file, itemPath .. ".enabled", true),
      defaultUnlocked = ba.config.getBooleanFrom(file, itemPath .. ".default_unlocked", false),
    }
  end
  return items
end

local function registerCategoryFromStore(key)
  local base = "category_settings." .. key
  local category = {
    id = ba.config.getStringFrom("store.yml", base .. ".id", key),
    displayName = ba.config.getStringFrom("store.yml", base .. ".name", key),
    icon = ba.config.getStringFrom("store.yml", base .. ".icon"),
    description = ba.config.getStringListFrom("store.yml", base .. ".description"),
    parentCategoryId = ba.config.getStringFrom("store.yml", base .. ".parent_id"),
    type = ba.config.getStringFrom("store.yml", base .. ".type", "SELECTION"),
    enabled = ba.config.getBooleanFrom("store.yml", base .. ".enabled", true),
    sortOrder = ba.config.getIntFrom("store.yml", base .. ".sort_order", 0),
    selectionEnabled = ba.config.getBooleanFrom("store.yml", base .. ".selection_enabled", true),
    randomSelectionEnabled = ba.config.getBooleanFrom("store.yml", base .. ".random_selection_enabled", false),
    randomItemDisplayName = ba.config.getStringFrom("store.yml", base .. ".random_item.display_name", "Random"),
    randomItemIcon = ba.config.getStringFrom("store.yml", base .. ".random_item.icon"),
    randomItemDescription = ba.config.getStringListFrom("store.yml", base .. ".random_item.description"),
  }

  local items
  if key == "kits" then
    items = readItemsFrom("kits.yml", "kits.order", "kits", "CHEST")
  elseif key == "cages" then
    items = readItemsFrom("cage.yml", "cages.order", "cages", "GLASS")
  else
    items = readItemsFrom("store.yml", base .. ".items.order", base .. ".items", "CHEST")
  end
  ba.store.registerCategory(category, items)
end

-- Registers every store.yml category (root, kits, cages) unconditionally, same as legacy.
function M.registerStoreItems()
  for _, key in ipairs(ba.config.getStringListFrom("store.yml", "categories")) do
    registerCategoryFromStore(key)
  end
end

return M

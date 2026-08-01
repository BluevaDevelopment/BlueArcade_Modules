-- Mirrors legacy RunFromTheBeastStoreService's registration + resolveSelected helpers.
local M = {}

local function readItems(base)
  local items = {}
  for _, itemId in ipairs(ba.config.getStringListFrom("store.yml", base .. ".items.order")) do
    local itemPath = base .. ".items." .. itemId
    items[#items + 1] = {
      id = itemId,
      displayName = ba.config.getStringFrom("store.yml", itemPath .. ".name", itemId),
      icon = ba.config.getStringFrom("store.yml", itemPath .. ".icon"),
      description = ba.config.getStringListFrom("store.yml", itemPath .. ".description"),
      price = ba.config.getIntFrom("store.yml", itemPath .. ".price", 0),
      enabled = ba.config.getBooleanFrom("store.yml", itemPath .. ".enabled", true),
      defaultUnlocked = ba.config.getBooleanFrom("store.yml", itemPath .. ".default_unlocked", false),
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
  ba.store.registerCategory(category, readItems(base))
end

-- Registers every store.yml category (root, beast_skins, zappers, kits, beast_pass) unconditionally, same as legacy.
function M.registerStoreItems()
  for _, key in ipairs(ba.config.getStringListFrom("store.yml", "categories")) do
    registerCategoryFromStore(key)
  end
end

-- Mirrors RunFromTheBeastStoreService.resolveSelected("beast_skins"); nil when unconfigured/unselected.
function M.resolveBeastSkin(session, beastHandle)
  local categoryId = session.config.getStringFrom("store.yml", "category_settings.beast_skins.id", "rftb_beast_skins")
  return session.store.resolveSelected(beastHandle, categoryId)
end

-- Mirrors RunFromTheBeastBeastService.buildBeastWeights's beast_pass ownership check.
function M.hasBeastPass(session, handle)
  local categoryId = session.config.getStringFrom("store.yml", "category_settings.beast_pass.id", "rftb_beast_pass")
  return session.store.isUnlocked(handle, categoryId, "pass")
end

return M

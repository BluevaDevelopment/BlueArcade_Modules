-- Mirrors legacy LootService.java + TrackedChest.java. The weighted-random item roll and the
-- MATERIAL:AMOUNT:WEIGHT / MATERIAL:MIN:MAX:WEIGHT[|ENCHANT:LEVEL,...] entry parsing both stay in
-- Lua (pure data, matching how every other module's own random-outcome logic already works) -
-- session.world.fillContainer/dropEnchantedItemAt only handle the real Bukkit mechanics
-- (multi-enchantment ItemStacks, container slot placement), the first module needing more than
-- one enchantment on a single item.
local M = {}

local function isChestMaterial(material)
  return material == "CHEST" or material == "TRAPPED_CHEST" or material == "ENDER_CHEST"
end
M.isChestMaterial = isChestMaterial

local function blockKey(x, y, z)
  return x .. ":" .. y .. ":" .. z
end

local function resolveChestTier(session)
  local tier = session.state.selectedChestTier
  if not tier or tier == "" then
    tier = session.config.getString("votes.defaults.chests") or "normal"
  end
  return tier:lower()
end

local function parseEntryEnchantments(raw)
  local enchantments = {}
  if not raw or raw == "" then
    return enchantments
  end
  for pair in raw:gmatch("[^,]+") do
    local name, level = pair:match("^%s*([%a_]+):(%d+)%s*$")
    if name and level then
      enchantments[#enchantments + 1] = { name = name, level = tonumber(level) }
    end
  end
  return enchantments
end

local function parseEntries(session, tier)
  local basePath = "loot.chests.tiers." .. tier
  local items = session.config.getStringList(basePath .. ".items")
  if #items == 0 then
    items = session.config.getStringList("loot.chests.items")
  end

  local parsed = {}
  for _, entry in ipairs(items) do
    local itemSpec, enchantSpec = entry:match("^([^|]+)|?(.*)$")
    local parts = {}
    for part in itemSpec:gmatch("[^:]+") do
      parts[#parts + 1] = part
    end
    if #parts >= 3 then
      local material = parts[1]:upper()
      local min = tonumber(parts[2])
      local max, weight
      if #parts >= 4 then
        max = tonumber(parts[3])
        weight = tonumber(parts[4])
      else
        max = min
        weight = tonumber(parts[3])
      end
      if min and weight and weight > 0 then
        parsed[#parsed + 1] = {
          material = material,
          minAmount = math.max(1, min),
          maxAmount = math.max(min, max or min),
          weight = weight,
          enchantments = parseEntryEnchantments(enchantSpec),
        }
      end
    end
  end
  return parsed
end

local function pickEntry(entries)
  local total = 0
  for _, entry in ipairs(entries) do
    total = total + entry.weight
  end
  if total <= 0 then
    return nil
  end
  local roll = math.random(0, total - 1)
  local count = 0
  for _, entry in ipairs(entries) do
    count = count + entry.weight
    if roll < count then
      return entry
    end
  end
  return entries[#entries]
end

local function rollItem(entry)
  local amount = entry.minAmount
  if entry.maxAmount > entry.minAmount then
    amount = math.random(entry.minAmount, entry.maxAmount)
  end
  return { material = entry.material, amount = amount, enchantments = entry.enchantments }
end

local function resolveMinItems(session, tier)
  local path = "loot.chests.tiers." .. tier .. ".item_count.min"
  if session.config.contains(path) then
    return session.config.getInt(path, 3)
  end
  return session.config.getInt("loot.chests.item_count.min", 3)
end

local function resolveMaxItems(session, tier)
  local path = "loot.chests.tiers." .. tier .. ".item_count.max"
  if session.config.contains(path) then
    return session.config.getInt(path, 6)
  end
  return session.config.getInt("loot.chests.item_count.max", 6)
end

local function rollItems(session, tier, count)
  local entries = parseEntries(session, tier)
  if #entries == 0 then
    return {}
  end
  local items = {}
  for _ = 1, count do
    local entry = pickEntry(entries)
    if entry then
      items[#items + 1] = rollItem(entry)
    end
  end
  return items
end

local function resolveNextRefillAt(session, now)
  local intervalSeconds = session.config.getInt("loot.refill.interval_seconds", 0)
  if not session.config.getBoolean("loot.refill.enabled", true) or intervalSeconds <= 0 then
    return math.huge
  end
  return now + intervalSeconds
end

local function rollItemCount(session, tier)
  local minItems = math.max(1, resolveMinItems(session, tier))
  local maxItems = math.max(minItems, resolveMaxItems(session, tier))
  return math.random(minItems, maxItems)
end

function M.handleChestLoot(session, handle, x, y, z, blockType)
  if not isChestMaterial(blockType) then
    return
  end
  local key = blockKey(x, y, z)
  if session.state.playerPlacedBlocks[key] then
    return
  end
  session.state.trackedChests[key] = { x = x, y = y, z = z, material = blockType }

  local now = os.clock()
  local refillAt = session.state.chestRefillTimes[key]
  if refillAt and now < refillAt then
    return
  end

  local tier = resolveChestTier(session)
  local items = rollItems(session, tier, rollItemCount(session, tier))
  if #items == 0 then
    return
  end
  if not session.world.fillContainer(x, y, z, items) then
    return
  end

  session.state.chestRefillTimes[key] = resolveNextRefillAt(session, now)
  session.world.spawnParticleAt({ x = x + 0.5, y = y + 1.0, z = z + 0.5 }, "FLAME", 20, 0.4, 0.4, 0.4, 0.01)
  session.stats.add(handle, "chests_looted", 1)
end

-- Returns true if this break was fully handled here (loot dropped, block removed) - the caller
-- cancels the real BlockBreakEvent when this is true, matching legacy's own return-value contract.
function M.handleChestBreak(session, handle, x, y, z, blockType)
  if not isChestMaterial(blockType) then
    return false
  end
  local key = blockKey(x, y, z)
  if session.state.playerPlacedBlocks[key] then
    return false
  end
  session.state.trackedChests[key] = { x = x, y = y, z = z, material = blockType }

  local now = os.clock()
  local refillAt = session.state.chestRefillTimes[key]
  if refillAt and now < refillAt then
    return false
  end

  local tier = resolveChestTier(session)
  local items = rollItems(session, tier, rollItemCount(session, tier))
  if #items == 0 then
    return false
  end

  local dropLocation = { x = x + 0.5, y = y + 0.5, z = z + 0.5 }
  session.world.setBlockType(x, y, z, "AIR")
  session.world.spawnParticleAt(dropLocation, "FLAME", 20, 0.4, 0.4, 0.4, 0.01)
  for _, item in ipairs(items) do
    session.world.dropEnchantedItemAt(dropLocation, item)
  end

  session.state.chestRefillTimes[key] = resolveNextRefillAt(session, now)
  if handle then
    session.stats.add(handle, "chests_looted", 1)
  end
  return true
end

local function refillTrackedChest(session, chest, now)
  local blockType = session.world.blockTypeAt(chest.x, chest.y, chest.z)
  if blockType == "AIR" then
    session.world.setBlockType(chest.x, chest.y, chest.z, chest.material)
    blockType = chest.material
  end
  if not isChestMaterial(blockType) then
    return
  end

  local tier = resolveChestTier(session)
  local items = rollItems(session, tier, rollItemCount(session, tier))
  if #items == 0 then
    return
  end
  if session.world.fillContainer(chest.x, chest.y, chest.z, items) then
    session.state.chestRefillTimes[blockKey(chest.x, chest.y, chest.z)] = resolveNextRefillAt(session, now)
  end
end

function M.restoreChests(session)
  for _, chest in pairs(session.state.trackedChests) do
    session.world.setBlockType(chest.x, chest.y, chest.z, chest.material)
  end
end

function M.startChestRefills(session)
  local intervalSeconds = session.config.getInt("loot.refill.interval_seconds", 0)
  if not session.config.getBoolean("loot.refill.enabled", true) or intervalSeconds <= 0 then
    return
  end

  local checkInterval = math.max(10, session.config.getInt("loot.refill.check_interval_ticks", 20))
  local taskId = "arena_" .. session.arenaId .. "_skywars_chest_refill"
  session.scheduler.runTimer(taskId, function()
    local now = os.clock()
    for _, chest in pairs(session.state.trackedChests) do
      local refillAt = session.state.chestRefillTimes[blockKey(chest.x, chest.y, chest.z)]
      if not refillAt or now >= refillAt then
        refillTrackedChest(session, chest, now)
      end
    end
  end, checkInterval, checkInterval)
end

function M.forceRefillChests(session)
  local now = os.clock()
  for _, chest in pairs(session.state.trackedChests) do
    refillTrackedChest(session, chest, now)
  end
end

return M

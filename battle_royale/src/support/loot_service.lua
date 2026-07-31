-- Mirrors legacy LootService.java + TrackedChest.java (a tracked chest is just a plain
-- {x,y,z,material} table in session.state.trackedChests, keyed the same block-coordinate way as
-- everywhere else in this binding layer). handleChestExplosion (EntityExplodeEvent/
-- BlockExplodeEvent-triggered loot) isn't ported - the v1 event catalogue has no
-- entity_explode/block_explode mapping yet, a real, deliberate gap for this rare edge case
-- (TNT/creeper explosions destroying a chest); the primary interact/break loot paths both work.
local M = {}

local function blockKey(x, y, z)
  return x .. ":" .. y .. ":" .. z
end

local function parseEntries(session, path)
  local entries = {}
  for _, line in ipairs(session.config.getStringList(path)) do
    local parts = {}
    for part in line:gmatch("[^:]+") do
      parts[#parts + 1] = part
    end
    if #parts >= 4 then
      local min = tonumber(parts[2])
      local max = tonumber(parts[3])
      local weight = tonumber(parts[4])
      if min and max and weight and weight > 0 then
        entries[#entries + 1] = { material = parts[1], minAmount = math.max(1, min), maxAmount = math.max(min, max), weight = weight }
      end
    end
  end
  return entries
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

function M.isChestLooted(session, x, y, z)
  return session.state.lootedChests[blockKey(x, y, z)] == true
end

function M.isPlayerPlacedBlock(session, x, y, z)
  return session.state.playerPlacedBlocks[blockKey(x, y, z)] == true
end

function M.trackPlacedBlock(session, x, y, z)
  session.state.playerPlacedBlocks[blockKey(x, y, z)] = true
end

function M.untrackPlacedBlock(session, x, y, z)
  session.state.playerPlacedBlocks[blockKey(x, y, z)] = nil
end

function M.handleChestLoot(session, handle, x, y, z, blockType)
  local isNormalChest = blockType == "CHEST" or blockType == "TRAPPED_CHEST"
  local isSpecialChest = blockType == "ENDER_CHEST"
  if not isNormalChest and not isSpecialChest then
    return
  end

  -- Chests placed by players are plain vanilla chests: no loot, no tracking.
  if M.isPlayerPlacedBlock(session, x, y, z) then
    return
  end

  local key = blockKey(x, y, z)
  session.state.trackedChests[key] = session.state.trackedChests[key] or { x = x, y = y, z = z, material = blockType }

  if M.isChestLooted(session, x, y, z) then
    return
  end

  local entries = parseEntries(session, isSpecialChest and "loot.special_chests.items" or "loot.chests.items")
  if #entries == 0 then
    return
  end

  session.state.lootedChests[key] = true

  local countBase = isSpecialChest and "loot.special_chests.item_count" or "loot.chests.item_count"
  local minItems = session.config.getInt(countBase .. ".min", isSpecialChest and 4 or 3)
  local maxItems = session.config.getInt(countBase .. ".max", isSpecialChest and 8 or 6)
  local itemCount = math.random(math.max(1, minItems), math.max(minItems, maxItems))

  local dropLocation = { x = x + 0.5, y = y + 0.5, z = z + 0.5 }
  session.world.setBlockType(x, y, z, "AIR")
  session.world.spawnParticleAt(dropLocation, isSpecialChest and "DRAGON_BREATH" or "FLAME", 20, 0.4, 0.4, 0.4, 0.01)

  for _ = 1, itemCount do
    local entry = pickEntry(entries)
    if entry then
      local amount = entry.minAmount == entry.maxAmount and entry.minAmount or math.random(entry.minAmount, entry.maxAmount)
      session.world.dropItemAt(dropLocation, entry.material, math.max(1, amount))
    end
  end

  if handle then
    session.stats.add(handle, "chests_looted", 1)
  end
end

function M.restoreChests(session)
  for _, chest in pairs(session.state.trackedChests) do
    session.world.setBlockType(chest.x, chest.y, chest.z, chest.material)
  end
end

return M

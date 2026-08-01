--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

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

function M.applyRespawnEffects(session, handle)
  applyEffects(session, handle, "effects.respawn_effects")
end

function M.giveKnockbackStick(session, handle)
  local material = session.config.getString("items.knockback_stick.material") or "STICK"
  local amount = math.max(1, session.config.getInt("items.knockback_stick.amount", 1))
  local slot = session.config.getInt("items.knockback_stick.slot", 0)
  local level = math.max(1, session.config.getInt("items.knockback_stick.knockback_level", 3))
  local unbreakable = session.config.getBoolean("items.knockback_stick.unbreakable", true)
  local name = session.config.getString("items.knockback_stick.name")
  local lore = session.config.getStringList("items.knockback_stick.lore")

  session.player.giveEnchantedItem(handle, material, amount, slot, "KNOCKBACK", level, unbreakable, name, lore)
end

return M

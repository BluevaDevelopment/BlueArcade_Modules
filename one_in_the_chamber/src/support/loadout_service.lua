local M = {}

local function splitColon(text)
  local parts = {}
  for part in string.gmatch(text, "[^:]+") do
    parts[#parts + 1] = part
  end
  return parts
end

local function giveStartingItems(session, handle)
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

local function restoreHealthAndHunger(session, handle)
  session.player.setHealth(handle, session.player.maxHealth(handle))
  session.player.setFoodLevel(handle, 20)
  session.player.setSaturation(handle, 20.0)
end

function M.rewardKillArrow(session, handle)
  local reward = math.max(1, session.config.getInt("items.kill_reward_arrows", 1))
  session.player.giveItem(handle, "ARROW", reward, -1)
end

function M.ensureMinimumArrows(session, handle)
  local minimum = math.max(0, session.config.getInt("items.minimum_arrows", 1))
  if minimum == 0 then return end

  local current = session.player.countItem(handle, "ARROW")
  if current < minimum then
    session.player.giveItem(handle, "ARROW", minimum - current, -1)
  end
end

function M.prepareForStart(session, handle)
  session.player.setGameMode(handle, "SURVIVAL")
  restoreHealthAndHunger(session, handle)
  giveStartingItems(session, handle)
  M.ensureMinimumArrows(session, handle)
  applyEffects(session, handle, "effects.starting_effects")
  applyEffects(session, handle, "effects.respawn_effects")
end

function M.applyRespawnLoadout(session, handle)
  session.player.clearInventory(handle)
  session.player.clearArmor(handle)
  restoreHealthAndHunger(session, handle)
  giveStartingItems(session, handle)
  M.ensureMinimumArrows(session, handle)
  applyEffects(session, handle, "effects.starting_effects")
  applyEffects(session, handle, "effects.respawn_effects")
end

return M

--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy PlayerLoadoutService.java. Item/effect strings parse the same
-- "MATERIAL:AMOUNT:SLOT[:HEX_COLOR]" / "EFFECT:DURATION:AMPLIFIER" formats legacy uses.
local M = {}

local function resolveTeamSlot(session, handle)
  if not session.teams.isEnabled() then
    return -1
  end
  local team = session.teams.forPlayer(handle)
  if not team or not team.id or team.id == "" then
    return -1
  end
  for i, current in ipairs(session.teams.all()) do
    if current.id and current.id:lower() == team.id:lower() then
      return i
    end
  end
  return -1
end

local function giveItems(session, handle, items)
  if not items or #items == 0 then return end
  for _, itemString in ipairs(items) do
    local parts = {}
    for part in itemString:gmatch("[^:]+") do
      parts[#parts + 1] = part
    end
    if #parts >= 2 then
      local material = parts[1]
      local amount = tonumber(parts[2])
      local slot = #parts >= 3 and tonumber(parts[3]) or -1
      local hexColor = #parts >= 4 and parts[4] or nil
      if amount then
        session.player.giveItem(handle, material, amount, slot, hexColor)
      end
    end
  end
end

local function applyEffects(session, handle, effects)
  if not effects or #effects == 0 then return end
  for _, effectString in ipairs(effects) do
    local parts = {}
    for part in effectString:gmatch("[^:]+") do
      parts[#parts + 1] = part
    end
    if #parts >= 3 then
      local duration, amplifier = tonumber(parts[2]), tonumber(parts[3])
      if duration and amplifier then
        session.player.addPotionEffect(handle, parts[1], duration, amplifier, false, false)
      end
    end
  end
end

function M.giveStartingItems(session, handle)
  local teamSlot = resolveTeamSlot(session, handle)
  local items
  if teamSlot > 0 then
    items = session.config.getStringList("items.starting_items_by_team." .. teamSlot)
  end
  if not items or #items == 0 then
    items = session.config.getStringList("items.starting_items")
  end
  giveItems(session, handle, items)
end

function M.applyStartingEffects(session, handle)
  applyEffects(session, handle, session.config.getStringList("effects.starting_effects"))
end

function M.applyRespawnEffects(session, handle)
  applyEffects(session, handle, session.config.getStringList("effects.respawn_effects"))
end

function M.restoreVitals(session, handle)
  session.player.setHealth(handle, session.player.maxHealth(handle))
  session.player.setFoodLevel(handle, 20)
  session.player.setSaturation(handle, 20.0)
end

function M.handleKillRegeneration(session, killerHandle)
  local healAmount = session.config.getDouble("combat.kill_regeneration.health", 6.0)
  if healAmount <= 0 then return end
  local newHealth = math.min(session.player.maxHealth(killerHandle), session.player.health(killerHandle) + healAmount)
  session.player.setHealth(killerHandle, newHealth)
end

return M

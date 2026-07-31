-- Mirrors legacy PlayerLoadoutService.java. applyRespawnEffects (respawn_effects, e.g. a short
-- damage-resistance grace period) is real here - unlike battle_royale's dead copy of the same
-- method, capture_the_wool's respawn flow actually calls it every respawn.
local M = {}

local function parseParts(raw)
  local parts = {}
  for part in raw:gmatch("[^:]+") do
    parts[#parts + 1] = part
  end
  return parts
end

local function resolveTeamSlot(session, handle)
  if not session.teams.isEnabled() then
    return -1
  end
  local team = session.teams.forPlayer(handle)
  if not team or not team.id or team.id == "" then
    return -1
  end
  local teams = session.teams.all()
  for i, current in ipairs(teams) do
    if current.id and current.id:lower() == team.id:lower() then
      return i
    end
  end
  return -1
end

local function giveItems(session, handle, items)
  for _, itemStr in ipairs(items) do
    local parts = parseParts(itemStr)
    if #parts >= 2 then
      local amount = tonumber(parts[2])
      local slot = parts[3] and tonumber(parts[3]) or -1
      local hexColor = parts[4]
      if amount then
        session.player.giveItem(handle, parts[1], amount, slot, hexColor)
      end
    end
  end
end

function M.giveStartingItems(session, handle)
  local teamSlot = resolveTeamSlot(session, handle)
  local items = nil
  if teamSlot > 0 then
    items = session.config.getStringList("items.starting_items_by_team." .. teamSlot)
  end
  if not items or #items == 0 then
    items = session.config.getStringList("items.starting_items")
  end
  giveItems(session, handle, items)
end

local function applyEffects(session, handle, path)
  for _, effectStr in ipairs(session.config.getStringList(path)) do
    local parts = parseParts(effectStr)
    if #parts >= 3 then
      local duration = tonumber(parts[2])
      local amplifier = tonumber(parts[3])
      if duration and amplifier then
        session.player.addPotionEffect(handle, parts[1], duration, amplifier)
      end
    end
  end
end

function M.applyStartingEffects(session, handle)
  applyEffects(session, handle, "effects.starting_effects")
end

function M.applyRespawnEffects(session, handle)
  applyEffects(session, handle, "effects.respawn_effects")
end

function M.restoreVitals(session, handle)
  session.player.setHealth(handle, session.player.maxHealth(handle))
  session.player.setFoodLevel(handle, 20)
  session.player.setSaturation(handle, 20.0)
end

function M.handleKillRegeneration(session, killerHandle)
  local healAmount = session.config.getDouble("combat.kill_regeneration.health", 6.0)
  if healAmount <= 0 then
    return
  end
  local newHealth = math.min(session.player.maxHealth(killerHandle), session.player.health(killerHandle) + healAmount)
  session.player.setHealth(killerHandle, newHealth)
end

return M

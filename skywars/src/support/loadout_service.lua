-- Mirrors legacy PlayerLoadoutService.java. StoreAPI is unbound in Lua (no ba.store yet), so every
-- player gets kits.yml's default_kit - matching legacy's own storeAPI==null fallback path exactly.
-- applyRespawnEffects isn't ported - dead code, since skywars has no respawn mechanism at all.
local M = {}

local function parseParts(raw)
  local parts = {}
  for part in raw:gmatch("[^:]+") do
    parts[#parts + 1] = part
  end
  return parts
end

local function isInteger(value)
  local n = tonumber(value)
  return n ~= nil and n == math.floor(n)
end

local POTION_MATERIALS = { POTION = true, SPLASH_POTION = true, LINGERING_POTION = true }

-- Lua truthiness means the string "false" is truthy - parse to a real boolean before crossing into Kotlin.
local function toBool(str)
  return str == "true"
end

local function giveItems(session, handle, items)
  for _, itemStr in ipairs(items) do
    local parts = parseParts(itemStr)
    if #parts >= 2 then
      local material = parts[1]:upper()
      local amount = tonumber(parts[2])
      local slot = -1
      local metadataStart = 3
      if parts[3] and isInteger(parts[3]) then
        slot = tonumber(parts[3])
        metadataStart = 4
      end

      if amount then
        if POTION_MATERIALS[material] and parts[metadataStart] then
          local extended = parts[metadataStart + 1] ~= nil and toBool(parts[metadataStart + 1])
          local upgraded = parts[metadataStart + 2] ~= nil and toBool(parts[metadataStart + 2])
          session.player.givePotionItem(handle, amount, slot, parts[metadataStart], extended, upgraded)
        else
          session.player.giveItem(handle, material, amount, slot)
        end
      end
    end
  end
end

function M.giveStartingItems(session, handle)
  giveItems(session, handle, session.config.getStringList("items.starting_items"))
end

local function applyEffects(session, handle, effects)
  for _, effectStr in ipairs(effects) do
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
  applyEffects(session, handle, session.config.getStringList("effects.starting_effects"))
end

local function resolveSelectedKitId(session)
  -- storeAPI is always unavailable here (see file doc) - always resolves to kits.yml's default_kit.
  return session.config.getStringFrom("kits.yml", "default_kit", "none")
end

function M.applySelectedKit(session, handle)
  local kitId = resolveSelectedKitId(session)
  if not kitId or kitId == "" then
    return
  end
  local base = "kits." .. kitId
  giveItems(session, handle, session.config.getStringListFrom("kits.yml", base .. ".items"))
  applyEffects(session, handle, session.config.getStringListFrom("kits.yml", base .. ".effects"))
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

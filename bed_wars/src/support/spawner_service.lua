-- Mirrors legacy SpawnerService.java. SpawnerDefinition/SpawnerType are plain Lua tables.
-- Hologram/item-stand liveness self-healing isn't ported - a spawned handle is trusted to stay
-- valid until this module itself deletes it, same as every other converted module.
local M = {}

local SPAWNER_SCAN_LIMIT = 128
local ITEM_STAND_TYPES = { diamond = "DIAMOND_BLOCK", emerald = "EMERALD_BLOCK" }

local function resolveDataBasePath(session, section)
  if session.dataAccess.hasGameData("game.play_area." .. section) then
    return "game.play_area." .. section
  end
  return "game." .. section
end

local DEFAULT_INTERVAL_TICKS = { iron = 40, gold = 160, diamond = 600, emerald = 1200 }

local function defaultInterval(session, spawnerType)
  return session.config.getInt("spawners.defaults." .. spawnerType .. "_interval_ticks", DEFAULT_INTERVAL_TICKS[spawnerType] or 40)
end

local function defaultHologram(spawnerType)
  return spawnerType == "diamond" or spawnerType == "emerald"
end

local function distance(a, b)
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function resolveTeamForSpawnerByBed(session, spawnerLoc)
  local closestTeam = nil
  local closestDistance = math.huge
  for _, bed in ipairs(session.state.beds) do
    local d = distance(spawnerLoc, bed)
    if d < closestDistance then
      closestDistance = d
      closestTeam = bed.teamId
    end
  end
  return closestTeam
end

function M.loadSpawnerDefinitions(session)
  local definitions = {}
  local base = resolveDataBasePath(session, "spawners")

  local registryRaw = session.dataAccess.getGameDataString(base .. ".spawner_registry")
    or session.dataAccess.getGameDataString("game.spawner_registry")

  local ids, seen = {}, {}
  if registryRaw and registryRaw ~= "" then
    for id in registryRaw:gmatch("[^,]+") do
      local trimmed = id:match("^%s*(.-)%s*$")
      if trimmed ~= "" and not seen[trimmed] then
        seen[trimmed] = true
        ids[#ids + 1] = trimmed
      end
    end
  end

  if #ids == 0 then
    for i = 1, SPAWNER_SCAN_LIMIT do
      local path = base .. "." .. i .. ".type"
      if session.dataAccess.hasGameData(path) then
        ids[#ids + 1] = tostring(i)
      end
    end
  end

  for _, spawnerId in ipairs(ids) do
    local basePath = base .. "." .. spawnerId
    local typeRaw = session.dataAccess.getGameDataString(basePath .. ".type")
    if typeRaw and typeRaw ~= "" then
      local spawnerType = typeRaw:lower()
      if ITEM_STAND_TYPES[spawnerType] or spawnerType == "iron" or spawnerType == "gold" then
        local loc = session.dataAccess.getGameLocation(basePath .. ".location")
        if loc then
          local hologramRaw = session.dataAccess.getGameDataString(basePath .. ".hologram")
          local hologramEnabled
          if hologramRaw == "true" then
            hologramEnabled = true
          elseif hologramRaw == "false" then
            hologramEnabled = false
          else
            hologramEnabled = defaultHologram(spawnerType)
          end

          definitions[#definitions + 1] = {
            spawnerId = spawnerId,
            key = spawnerId:lower(),
            type = spawnerType,
            x = math.floor(loc.x), y = math.floor(loc.y), z = math.floor(loc.z),
            intervalTicks = defaultInterval(session, spawnerType),
            hologramEnabled = hologramEnabled,
            teamId = nil,
          }
        end
      end
    end
  end

  for _, def in ipairs(definitions) do
    if def.type == "iron" or def.type == "gold" then
      def.teamId = resolveTeamForSpawnerByBed(session, def)
    end
  end

  return definitions
end

function M.loadGeneratorUpgradeEvents(session)
  local events = {}
  if not session.config.getBoolean("generator_upgrades.enabled", false) then
    return events
  end

  local i = 1
  while true do
    local base = "generator_upgrades.events." .. i
    local timeSeconds = session.config.getInt(base .. ".time_seconds", -1)
    if timeSeconds < 0 then break end
    local eventType = session.config.getString(base .. ".type")
    local label = session.config.getString(base .. ".label") or "Generator Upgrade"
    local multiplier = session.config.getDouble(base .. ".multiplier", 2.0)
    if eventType and eventType ~= "" then
      events[#events + 1] = { triggerSeconds = timeSeconds, type = eventType:lower(), label = label, multiplier = multiplier }
    end
    i = i + 1
  end

  table.sort(events, function(a, b) return a.triggerSeconds < b.triggerSeconds end)
  return events
end

local function getSpawnerMultiplier(session, teamId, spawnerType)
  if teamId then
    local teamMultipliers = session.state.teamSpawnerMultiplier[teamId:lower()]
    local teamMultiplier = teamMultipliers and teamMultipliers[spawnerType]
    if teamMultiplier and teamMultiplier > 1.0 then
      return teamMultiplier
    end
  end
  return session.state.globalSpawnerMultiplier[spawnerType] or 1.0
end
M.getSpawnerMultiplier = getSpawnerMultiplier

function M.setTeamSpawnerMultiplier(session, teamId, spawnerType, multiplier)
  if not teamId then return end
  local key = teamId:lower()
  session.state.teamSpawnerMultiplier[key] = session.state.teamSpawnerMultiplier[key] or {}
  session.state.teamSpawnerMultiplier[key][spawnerType] = math.max(1.0, multiplier)
end

function M.spawnResources(session)
  for _, def in ipairs(session.state.spawners) do
    local ticks = (session.state.spawnerTicks[def.key] or 0) + 1
    session.state.spawnerTicks[def.key] = ticks
    local multiplier = getSpawnerMultiplier(session, def.teamId, def.type)
    local effectiveTicks = math.max(1, math.floor(def.intervalTicks / multiplier))
    if ticks >= effectiveTicks then
      session.state.spawnerTicks[def.key] = 0
      local dropLoc = { x = def.x + 0.5, y = def.y + 1.0, z = def.z + 0.5 }
      session.world.dropItemAt(dropLoc, ITEM_STAND_TYPES[def.type] or (def.type == "iron" and "IRON_INGOT" or "GOLD_INGOT"), 1)
    end
  end
end

local ROMAN_NUMERALS = { "I", "II", "III", "IV", "V" }

local function buildSpawnerHologramLines(session, def, remainingSeconds)
  local typeLabelKey = "messages.spawner.hologram_" .. def.type
  local typeLabel = session.config.translation(nil, typeLabelKey) or session.config.translation(nil, "messages.spawner.hologram_label") or "<white>{type}</white>"
  typeLabel = typeLabel:gsub("{type}", def.type:sub(1, 1):upper() .. def.type:sub(2))

  local multiplier = getSpawnerMultiplier(session, def.teamId, def.type)
  local tierTemplate = session.config.translation(nil, "messages.spawner.hologram_tier") or "<yellow>Tier {tier}</yellow>"
  local tier = math.max(1, math.floor(multiplier + 0.5))
  local tierLabel = tierTemplate:gsub("{tier}", ROMAN_NUMERALS[tier] or tostring(tier))

  local lines = { typeLabel, tierLabel }

  local timeUntilNextTier = nil
  local matchSeconds = session.state.matchSeconds
  for i, event in ipairs(session.state.scheduledEvents) do
    if not session.state.eventFired[i] and event.triggerSeconds > matchSeconds and event.type == def.type then
      local remaining = event.triggerSeconds - matchSeconds
      timeUntilNextTier = string.format("%02d:%02d", math.floor(remaining / 60), remaining % 60)
      break
    end
  end
  if timeUntilNextTier then
    local template = session.config.translation(nil, "messages.spawner.hologram_next_upgrade") or "<gray>(Next upgrade in <white>{time}</white>)</gray>"
    lines[#lines + 1] = template:gsub("{time}", timeUntilNextTier)
  end

  if remainingSeconds and remainingSeconds >= 0 then
    local template = session.config.translation(nil, "messages.spawner.hologram_countdown") or "<gray>Next drop in <white>{seconds}s</white></gray>"
    lines[#lines + 1] = template:gsub("{seconds}", string.format("%02d:%02d", math.floor(remainingSeconds / 60), remainingSeconds % 60))
  end

  return lines
end

local function spawnSpawnerItemStand(session, def)
  if session.state.spawnerItemStands[def.key] then
    return
  end
  local loc = { x = def.x + 0.5, y = def.y + 2.8, z = def.z + 0.5 }
  if not session.world.isChunkLoaded(math.floor(loc.x / 16), math.floor(loc.z / 16)) then
    return
  end
  local handle = session.world.spawnEntity(loc, "ARMOR_STAND")
  if not handle then return end
  session.entities.configureSpawnerItemStand(handle, ITEM_STAND_TYPES[def.type])
  session.state.spawnerItemStands[def.key] = handle
  session.state.spawnerItemRotation[def.key] = 0
end

function M.spawnSpawnerHolograms(session)
  for _, def in ipairs(session.state.spawners) do
    if def.hologramEnabled then
      local holoLoc = { x = def.x + 0.5, y = def.y + 2.5, z = def.z + 0.5 }
      if session.world.isChunkLoaded(math.floor(holoLoc.x / 16), math.floor(holoLoc.z / 16)) and not session.state.spawnerHolograms[def.key] then
        local lines = buildSpawnerHologramLines(session, def, nil)
        local hologram = session.hologram.spawn(holoLoc, lines)
        if hologram then
          session.state.spawnerHolograms[def.key] = hologram
        end
      end
      if ITEM_STAND_TYPES[def.type] then
        spawnSpawnerItemStand(session, def)
      end
    end
  end
end

function M.updateSpawnerHolograms(session)
  for _, def in ipairs(session.state.spawners) do
    local hologram = session.state.spawnerHolograms[def.key]
    if def.hologramEnabled and hologram then
      local multiplier = getSpawnerMultiplier(session, def.teamId, def.type)
      local effectiveTicks = math.max(1, math.floor(def.intervalTicks / multiplier))
      local currentTicks = session.state.spawnerTicks[def.key] or 0
      local remainingTicks = effectiveTicks - currentTicks
      local remainingSeconds = math.max(0, math.floor((remainingTicks + 19) / 20))
      session.hologram.setLines(hologram, buildSpawnerHologramLines(session, def, remainingSeconds))
    end
  end
end

function M.rotateSpawnerItems(session)
  for key, handle in pairs(session.state.spawnerItemStands) do
    if session.entities.isValid(handle) then
      local rotation = ((session.state.spawnerItemRotation[key] or 0) + 4) % 360
      session.state.spawnerItemRotation[key] = rotation
      session.entities.setHeadPose(handle, rotation)
    end
  end
end

function M.isSpawnerLocation(session, x, y, z)
  for _, def in ipairs(session.state.spawners) do
    if def.x == x and def.y == y and def.z == z then
      return true
    end
  end
  return false
end

function M.clearSpawnerHolograms(session)
  for key, hologram in pairs(session.state.spawnerHolograms) do
    session.hologram.delete(hologram)
    session.state.spawnerHolograms[key] = nil
  end
  for key, handle in pairs(session.state.spawnerItemStands) do
    session.entities.remove(handle)
    session.state.spawnerItemStands[key] = nil
  end
end

return M

local messageService = require("support.message_service")

local M = {}

local function locationKey(x, y, z)
  return x .. "," .. y .. "," .. z
end

local function parseLocationKey(key)
  local x, y, z = string.match(key, "(-?%d+),(-?%d+),(-?%d+)")
  return tonumber(x), tonumber(y), tonumber(z)
end

local function directionFromLocation(loc)
  local yawRad = math.rad(loc.yaw)
  local pitchRad = math.rad(loc.pitch)
  local xz = math.cos(pitchRad)
  return {
    x = -xz * math.sin(yawRad),
    y = -math.sin(pitchRad),
    z = xz * math.cos(yawRad),
  }
end

local function isInsideBounds(location, min, max)
  if min == nil or max == nil then return false end
  return location.x >= math.min(min.x, max.x) and location.x <= math.max(min.x, max.x)
      and location.y >= math.min(min.y, max.y) and location.y <= math.max(min.y, max.y)
      and location.z >= math.min(min.z, max.z) and location.z <= math.max(min.z, max.z)
end

local function getMineSpawnChance(session)
  local chance = session.config.getDouble("mines.spawn_chance", 0)
  if chance > 1 then chance = chance / 100.0 end
  if chance <= 0 then chance = 0.5 end
  return math.min(1.0, math.max(0.0, chance))
end

-- Only names ending in PRESSURE_PLATE count (matches getPlateMaterials' filter); invalid material
-- names are left to setBlockType's own silent failure rather than validated here.
local function getPlateMaterials(session)
  local names = session.config.getStringList("mines.plate_materials")
  local plates = {}
  for _, name in ipairs(names) do
    local upper = string.upper(name)
    if string.sub(upper, -14) == "PRESSURE_PLATE" then
      plates[#plates + 1] = upper
    end
  end
  return plates
end

function M.isMineMaterial(session, materialName)
  local plates = getPlateMaterials(session)
  if #plates == 0 then
    return materialName == "STONE_PRESSURE_PLATE" or materialName == "LIGHT_WEIGHTED_PRESSURE_PLATE"
  end
  for _, plate in ipairs(plates) do
    if plate == materialName then return true end
  end
  return false
end

function M.clearMineBlocks(session)
  for key in pairs(session.state.mines) do
    local x, y, z = parseLocationKey(key)
    local blockType = session.world.blockTypeAt(x, y, z)
    if M.isMineMaterial(session, blockType) then
      session.world.setBlockType(x, y, z, "AIR")
    end
  end
  session.state.mines = {}
end

function M.placeMines(session)
  local floorMin = session.dataAccess.getGameLocation("game.floor.bounds.min")
  local floorMax = session.dataAccess.getGameLocation("game.floor.bounds.max")
  if floorMin == nil or floorMax == nil then return end

  local spawnChance = getMineSpawnChance(session)
  M.clearMineBlocks(session)

  local minX, maxX = math.min(math.floor(floorMin.x), math.floor(floorMax.x)), math.max(math.floor(floorMin.x), math.floor(floorMax.x))
  local minZ, maxZ = math.min(math.floor(floorMin.z), math.floor(floorMax.z)), math.max(math.floor(floorMin.z), math.floor(floorMax.z))
  local plateY = math.min(math.floor(floorMin.y), math.floor(floorMax.y)) + 1

  local plates = getPlateMaterials(session)
  if #plates == 0 then plates = { "STONE_PRESSURE_PLATE" } end

  local finishMin = session.dataAccess.getGameLocation("game.finish_line.bounds.min")
  local finishMax = session.dataAccess.getGameLocation("game.finish_line.bounds.max")

  for x = minX, maxX do
    for z = minZ, maxZ do
      local plateLocation = { x = x, y = plateY, z = z, yaw = 0, pitch = 0 }

      if not isInsideBounds(plateLocation, finishMin, finishMax)
          and session.world.blockTypeAt(x, plateY - 1, z) ~= "AIR" then
        if math.random() <= spawnChance then
          local material = plates[math.random(#plates)]
          session.world.setBlockType(x, plateY, z, material)
          session.state.mines[locationKey(x, plateY, z)] = true
        elseif session.world.blockTypeAt(x, plateY, z) ~= "AIR" then
          session.world.setBlockType(x, plateY, z, "AIR")
        end
      end
    end
  end
end

function M.getActiveMineCount(session)
  local count = 0
  for _ in pairs(session.state.mines) do count = count + 1 end
  return count
end

function M.removeMineLocation(session, x, y, z)
  session.state.mines[locationKey(x, y, z)] = nil
end

local function hasMineImmunity(session, handle)
  local until_ = session.state.mineImmunity[handle]
  if until_ == nil then return false end
  -- os.clock() is used since immunity_millis (1200ms default) needs sub-second precision that
  -- os.time() can't provide, same reasoning as traffic_light's pushback window.
  if os.clock() > until_ then
    session.state.mineImmunity[handle] = nil
    return false
  end
  return true
end

local function grantMineImmunity(session, handle)
  local durationSeconds = session.config.getInt("mines.immunity_millis", 1200) / 1000
  session.state.mineImmunity[handle] = os.clock() + durationSeconds
end

function M.handleMineTrigger(session, handle, plateLocation)
  if hasMineImmunity(session, handle) then return end
  grantMineImmunity(session, handle)

  local verticalForce = session.config.getDouble("mines.explosion.vertical_force", 1.35)
  local backwardForce = session.config.getDouble("mines.explosion.backward_force", 1.05)
  local particleName = session.config.getString("mines.explosion.particle") or "EXPLOSION"
  local soundName = session.config.getString("mines.explosion.sound") or "ENTITY_GENERIC_EXPLODE"
  local teleportToSpawn = session.config.getBoolean("mines.teleport", false)

  local particleLocation = { x = plateLocation.x + 0.5, y = plateLocation.y + 0.2, z = plateLocation.z + 0.5, yaw = 0, pitch = 0 }
  if not session.world.spawnParticleAt(particleLocation, particleName, 1, 0, 0, 0) then
    session.world.spawnParticleAt(particleLocation, "EXPLOSION", 1, 0, 0, 0)
  end

  if not session.world.playSoundAt(plateLocation, soundName, 1.2, 1.0) then
    session.world.playSoundAt(plateLocation, "ENTITY_GENERIC_EXPLODE", 1.2, 1.0)
  end

  if teleportToSpawn then
    session.respawnPlayer(handle)
  else
    local direction = directionFromLocation(session.player.location(handle))
    session.player.setVelocity(handle, -direction.x * backwardForce, verticalForce, -direction.z * backwardForce)
  end

  local message = messageService.getMineTriggeredMessage(session)
  if message ~= nil then
    session.messages.sendRaw(handle, message)
  end

  session.stats.add(handle, "mines_triggered", 1)
end

return M

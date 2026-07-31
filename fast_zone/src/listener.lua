local gameManager = require("game_manager")

local AIR_MATERIALS = { AIR = true, CAVE_AIR = true, VOID_AIR = true }

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

local function normalize(v)
  local length = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
  if length == 0 then return v end
  return { x = v.x / length, y = v.y / length, z = v.z / length }
end

local function offset(loc, dx, dy, dz)
  return { x = loc.x + dx, y = loc.y + dy, z = loc.z + dz }
end

local function ignoredCollisionBlocks(session)
  local configured = session.config.getStringList("hazards.wall_collision.ignore_blocks")
  local set = {}
  for _, name in ipairs(configured) do
    set[string.upper(name)] = true
  end
  if next(set) == nil then
    return { AIR = true, CAVE_AIR = true, VOID_AIR = true }
  end
  return set
end

local function isBlocking(session, ignored, location)
  local material = session.world.blockTypeAt(math.floor(location.x), math.floor(location.y), math.floor(location.z))
  if ignored[material] or AIR_MATERIALS[material] then return false end
  return not session.world.isPassable(math.floor(location.x), math.floor(location.y), math.floor(location.z))
end

local function hasCollidedWithWall(session, target, eyeHeight)
  local direction = directionFromLocation(target)
  local lengthSquared = direction.x * direction.x + direction.y * direction.y + direction.z * direction.z
  if lengthSquared == 0 then return false end

  local distance = math.max(0.1, session.config.getDouble("hazards.wall_collision.check_distance", 1.0))
  local unit = normalize(direction)
  local eyeLocation = offset(target, 0, eyeHeight, 0)
  local aheadLocation = offset(eyeLocation, unit.x * distance, unit.y * distance, unit.z * distance)

  local ignored = ignoredCollisionBlocks(session)
  if isBlocking(session, ignored, aheadLocation) then return true end

  -- Only check head height, ignore feet to allow carpets and flowers
  return isBlocking(session, ignored, offset(target, 0, eyeHeight, 0))
end

local function isInsideFinishLine(session, location)
  local finishMin = session.dataAccess.getGameLocation("game.finish_line.bounds.min")
  local finishMax = session.dataAccess.getGameLocation("game.finish_line.bounds.max")
  if finishMin == nil or finishMax == nil then return false end

  return location.x >= math.min(finishMin.x, finishMax.x) and location.x <= math.max(finishMin.x, finishMax.x)
      and location.y >= math.min(finishMin.y, finishMax.y) and location.y <= math.max(finishMin.y, finishMax.y)
      and location.z >= math.min(finishMin.z, finishMax.z) and location.z <= math.max(finishMin.z, finishMax.z)
end

local function crossedFinishLine(session, from, to)
  if isInsideFinishLine(session, to) then return true end

  local dx, dy, dz = to.x - from.x, to.y - from.y, to.z - from.z
  local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
  if distance == 0 then return false end

  local steps = math.max(1, math.ceil(distance / 0.5))
  local stepX, stepY, stepZ = dx / steps, dy / steps, dz / steps
  local probeX, probeY, probeZ = from.x, from.y, from.z

  for _ = 0, steps do
    if isInsideFinishLine(session, { x = probeX, y = probeY, z = probeZ }) then return true end
    probeX = probeX + stepX
    probeY = probeY + stepY
    probeZ = probeZ + stepZ
  end

  return false
end

local M = {}

function M.register()
  ba.events.on("player_damage", function(session, e)
    if e.cause ~= "FALL" then return end
    if session.isPlaying(e.player) then e:cancel() end
  end)

  ba.events.on("player_move", function(session, e)
    if not session.isPlaying(e.player) then return end

    local sameBlock = math.floor(e.from.x) == math.floor(e.to.x)
        and math.floor(e.from.y) == math.floor(e.to.y)
        and math.floor(e.from.z) == math.floor(e.to.z)
    if sameBlock then return end

    if session.phase() == "COUNTDOWN" then
      e.setTo(e.from)
      return
    end

    if not session.isInsideBounds(e.to) then
      gameManager.playRespawnSound(session, e.player)
      session.visualEffects.playDeathEffect(e.player)
      gameManager.handlePlayerDeath(session, e.player, "messages.deaths.void")
      session.respawnPlayer(e.player)
      gameManager.handlePlayerRespawn(session, e.player)
      return
    end

    local eyeHeight = session.player.eyeHeight(e.player)
    local blockAtHeadType = session.world.blockTypeAt(math.floor(e.to.x), math.floor(e.to.y + eyeHeight), math.floor(e.to.z))

    local deathBlockName = session.dataAccess.getGameDataString("basic.death_block")
    local deathBlock = deathBlockName ~= nil and string.upper(deathBlockName) or "BARRIER"
    if blockAtHeadType == deathBlock then
      gameManager.playRespawnSound(session, e.player)
      session.visualEffects.playDeathEffect(e.player)
      gameManager.handlePlayerDeath(session, e.player, "messages.deaths.death_block")
      session.respawnPlayer(e.player)
      gameManager.handlePlayerRespawn(session, e.player)
      return
    end

    if session.config.getBoolean("hazards.wall_collision.enabled", true) and hasCollidedWithWall(session, e.to, eyeHeight) then
      gameManager.handleWallCollision(session, e.player)
      return
    end

    if crossedFinishLine(session, e.from, e.to) then
      session.finishPlayer(e.player)

      local position = 0
      for i, handle in ipairs(session.spectators()) do
        if handle == e.player then position = i end
      end

      gameManager.handlePlayerFinish(session, e.player)
      gameManager.broadcastFinish(session, e.player, position)

      local subtitle = string.gsub(session.config.translation(e.player, "titles.finished.subtitle"), "{position}", tostring(position))
      session.titles.sendRaw(e.player, session.config.translation(e.player, "titles.finished.title"), subtitle, 0, 80, 20)
      gameManager.playFinishSound(session, e.player)
    end
  end)
end

return M

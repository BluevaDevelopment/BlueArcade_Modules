--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local M = {}

function M.resolveMaxJumps(session)
  local defaultUses = session.config.getInt("double_jump.default_uses", 0)
  local maxUses = session.config.getInt("double_jump.max_uses", 10)
  local value = session.dataAccess.getGameDataNumber("basic.double_jump_uses")
  local uses = value ~= nil and math.floor(value) or defaultUses
  return math.min(maxUses, math.max(0, uses))
end

function M.initializeJumps(session, handle)
  if session.state.maxDoubleJumps <= 0 then return end
  session.state.doubleJumps[handle] = session.state.maxDoubleJumps
end

function M.getRemainingJumps(session, handle)
  return session.state.doubleJumps[handle] or 0
end

function M.clearJumps(session, handle, updateFlightState)
  session.state.doubleJumps[handle] = nil
  if updateFlightState ~= false then
    session.player.setAllowFlight(handle, false)
    session.player.setFlying(handle, false)
  end
end

local function resolveVerticalBoost(session)
  local value = session.dataAccess.getGameDataNumber("basic.double_jump_vertical_boost")
  if value ~= nil then return value end
  return session.config.getDouble("double_jump.boost.vertical", 0.8)
end

local function resolveHorizontalBoost(session)
  local value = session.dataAccess.getGameDataNumber("basic.double_jump_horizontal_boost")
  if value ~= nil then return value end
  return session.config.getDouble("double_jump.boost.horizontal", 0.8)
end

-- horizontal-only direction from yaw (pitch cancels after setY(0):normalize() in the original).
local function horizontalDirection(location)
  local yawRad = math.rad(location.yaw or 0)
  return -math.sin(yawRad), math.cos(yawRad)
end

function M.performDoubleJump(session, handle)
  local remaining = M.getRemainingJumps(session, handle)
  if remaining <= 0 then
    session.player.setAllowFlight(handle, false)
    session.player.setFlying(handle, false)
    return false
  end

  session.state.doubleJumps[handle] = remaining - 1

  local horizontalBoost = resolveHorizontalBoost(session)
  local verticalBoost = resolveVerticalBoost(session)

  session.player.setFlying(handle, false)
  local dirX, dirZ = horizontalDirection(session.player.location(handle))

  local velocity = session.player.getVelocity(handle)
  local vx, vz
  if (velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z) > 0.01 then
    vx = velocity.x * 1.2 + dirX * horizontalBoost
    vz = velocity.z * 1.2 + dirZ * horizontalBoost
  else
    vx = dirX * horizontalBoost
    vz = dirZ * horizontalBoost
  end

  session.player.setVelocity(handle, vx, verticalBoost, vz)
  session.sounds.play(handle, session.coreConfig.getSound("sounds.in_game.double_jump"))

  if M.getRemainingJumps(session, handle) <= 0 then
    session.scheduler.runLater("arena_" .. session.arenaId .. "_tnt_run_disable_flight_" .. handle, function()
      session.player.setAllowFlight(handle, false)
    end, 5)
  end

  return true
end

return M

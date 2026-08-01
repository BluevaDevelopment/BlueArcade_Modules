-- "Distance to the beast" is just the player's own real XP bar (session.player.setExp).
local M = {}

function M.resetDistanceBar(session, handle)
  session.player.setExp(handle, 0.0)
end

function M.resetDistanceBars(session)
  for _, handle in ipairs(session.players()) do
    M.resetDistanceBar(session, handle)
  end
end

local function calculateDistanceProgress(distance, minDistance, maxDistance)
  if maxDistance <= minDistance then
    return 1.0
  end
  local clamped = math.min(math.max(distance, minDistance), maxDistance)
  local ratio = (clamped - minDistance) / (maxDistance - minDistance)
  return math.max(0.0, math.min(1.0, 1.0 - ratio))
end

local function distanceBetween(a, b)
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function M.updateDistanceBars(session, beast)
  if not beast then
    M.resetDistanceBars(session)
    return
  end

  local minDistance = session.config.getDouble("distance_bar.min_distance", 3.0)
  local maxDistance = session.config.getDouble("distance_bar.max_distance", 60.0)
  local beastLocation = session.player.location(beast)

  for _, handle in ipairs(session.alivePlayers()) do
    if handle == beast then
      M.resetDistanceBar(session, handle)
    else
      local distance = distanceBetween(session.player.location(handle), beastLocation)
      session.player.setExp(handle, calculateDistanceProgress(distance, minDistance, maxDistance))
    end
  end
end

return M

local M = {}

local function isSpectator(session, handle)
  for _, spectator in ipairs(session.spectators()) do
    if spectator == handle then return true end
  end
  return false
end

local function getDistanceToFinish(session, handle)
  local finishMin = session.dataAccess.getGameLocation("game.finish_line.bounds.min")
  local finishMax = session.dataAccess.getGameLocation("game.finish_line.bounds.max")
  if finishMin == nil or finishMax == nil then return nil end

  local centerX = (finishMin.x + finishMax.x) / 2
  local centerY = (finishMin.y + finishMax.y) / 2
  local centerZ = (finishMin.z + finishMax.z) / 2

  local location = session.player.location(handle)
  local dx = location.x - centerX
  local dy = location.y - centerY
  local dz = location.z - centerZ
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function M.formatDistance(session, handle)
  if isSpectator(session, handle) then return "0" end

  local distance = getDistanceToFinish(session, handle)
  if distance == nil then return "?" end
  return string.format("%.0f", distance)
end

-- Spectators first in finish order (session.spectators() insertion order, same convention as
-- fast_zone), then alive players sorted ascending by distance to the finish line.
function M.getTopPlayersByDistance(session)
  local topPlayers = {}
  for _, spectator in ipairs(session.spectators()) do
    topPlayers[#topPlayers + 1] = spectator
  end

  local aliveWithDistance = {}
  for _, handle in ipairs(session.alivePlayers()) do
    aliveWithDistance[#aliveWithDistance + 1] = { handle = handle, distance = getDistanceToFinish(session, handle) or math.huge }
  end
  table.sort(aliveWithDistance, function(a, b) return a.distance < b.distance end)

  for _, entry in ipairs(aliveWithDistance) do
    topPlayers[#topPlayers + 1] = entry.handle
  end

  return topPlayers
end

function M.calculateLivePosition(session, handle)
  local spectators = session.spectators()
  for i, spectator in ipairs(spectators) do
    if spectator == handle then return i end
  end

  local aliveWithDistance = {}
  for _, h in ipairs(session.alivePlayers()) do
    aliveWithDistance[#aliveWithDistance + 1] = { handle = h, distance = getDistanceToFinish(session, h) or math.huge }
  end
  table.sort(aliveWithDistance, function(a, b) return a.distance < b.distance end)

  for i, entry in ipairs(aliveWithDistance) do
    if entry.handle == handle then return #spectators + i end
  end

  return #spectators + #aliveWithDistance
end

function M.getCustomPlaceholders(session, handle)
  local placeholders = { minefield_position = tostring(M.calculateLivePosition(session, handle)) }

  local topPlayers = M.getTopPlayersByDistance(session)
  for i = 1, 5 do
    local topHandle = topPlayers[i]
    placeholders["place_" .. i] = topHandle ~= nil and session.player.name(topHandle) or "-"
  end

  return placeholders
end

return M

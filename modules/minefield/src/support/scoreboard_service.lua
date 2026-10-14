--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local M = {}

local function isFinisher(session, handle)
  for _, finisher in ipairs(session.state.finishedPlayers or {}) do
    if finisher == handle then return true end
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
  if isFinisher(session, handle) then return "0" end

  local distance = getDistanceToFinish(session, handle)
  if distance == nil then return "?" end
  return tostring(math.floor(distance + 0.5))
end

-- Real finishers in crossing order, then alive players sorted by distance.
function M.getTopPlayersByDistance(session)
  local topPlayers = {}
  for _, finisher in ipairs(session.state.finishedPlayers or {}) do
    topPlayers[#topPlayers + 1] = finisher
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
  local finishers = session.state.finishedPlayers or {}
  for i, finisher in ipairs(finishers) do
    if finisher == handle then return i end
  end

  local aliveWithDistance = {}
  for _, h in ipairs(session.alivePlayers()) do
    aliveWithDistance[#aliveWithDistance + 1] = { handle = h, distance = getDistanceToFinish(session, h) or math.huge }
  end
  table.sort(aliveWithDistance, function(a, b) return a.distance < b.distance end)

  for i, entry in ipairs(aliveWithDistance) do
    if entry.handle == handle then return #finishers + i end
  end

  return 0
end

function M.getCustomPlaceholders(session, handle)
  local position = M.calculateLivePosition(session, handle)
  local placeholders = { minefield_position = position > 0 and tostring(position) or "-" }

  local topPlayers = M.getTopPlayersByDistance(session)
  for i = 1, 5 do
    local topHandle = topPlayers[i]
    placeholders["place_" .. i] = topHandle ~= nil and session.player.name(topHandle) or "-"
  end

  return placeholders
end

return M

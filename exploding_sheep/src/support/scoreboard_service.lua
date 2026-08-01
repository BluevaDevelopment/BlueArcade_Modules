local M = {}

local function formatCountdownTime(seconds)
  if seconds < 0 then seconds = 0 end
  return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function shearsOf(session, handle)
  return session.state.sheared[handle] or 0
end

local function countSheep(session)
  local count = 0
  for _ in pairs(session.state.sheep) do count = count + 1 end
  return count
end

function M.getCustomPlaceholders(session, handle)
  return {
    alive = tostring(#session.alivePlayers()),
    total_players = tostring(#session.players()),
    spectators = tostring(#session.spectators()),
    sheared_sheep = tostring(shearsOf(session, handle)),
    active_sheep = tostring(countSheep(session)),
    time = formatCountdownTime(session.state.timeLeft),
  }
end

-- Sorted by shears desc, ties by name; falls back to every player when nobody is alive.
function M.getTopPlayersByShears(session)
  local candidates = session.alivePlayers()
  if #candidates == 0 then
    candidates = session.players()
  end

  table.sort(candidates, function(a, b)
    local shearsA, shearsB = shearsOf(session, a), shearsOf(session, b)
    if shearsA ~= shearsB then return shearsA > shearsB end
    return string.lower(session.player.name(a)) < string.lower(session.player.name(b))
  end)

  local leaderboard = {}
  for i = 1, math.min(5, #candidates) do
    leaderboard[#leaderboard + 1] = candidates[i]
  end
  return leaderboard
end

function M.getScoreboardPlaceholders(session, handle)
  local placeholders = M.getCustomPlaceholders(session, handle)
  placeholders.round = tostring(session.currentRound)
  placeholders.round_max = tostring(session.maxRounds)
  placeholders.alive_total = placeholders.alive .. "/" .. placeholders.total_players

  local leaderboard = M.getTopPlayersByShears(session)
  for i = 1, 5 do
    local topHandle = leaderboard[i]
    if topHandle ~= nil then
      placeholders["place_" .. i] = session.player.name(topHandle)
      placeholders["shears_" .. i] = tostring(shearsOf(session, topHandle))
    else
      placeholders["place_" .. i] = "-"
      placeholders["shears_" .. i] = "0"
    end
  end

  return placeholders
end

return M

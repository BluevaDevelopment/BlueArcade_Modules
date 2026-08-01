local M = {}

local function getWinMode(session)
  local mode = session.dataAccess.getGameDataString("basic.win_mode")
  if mode == nil then return "last_standing" end
  mode = string.lower(mode)
  if mode ~= "last_standing" and mode ~= "most_kills" then return "last_standing" end
  return mode
end

local function getKills(session, handle)
  return session.state.kills[handle] or 0
end

local function getModeLabel(session, handle, mode)
  if mode == "most_kills" then
    return session.config.translation(handle, "scoreboard.mode_labels.most_kills")
  end
  return session.config.translation(handle, "scoreboard.mode_labels.last_standing")
end

-- Sorted descending by kills, ties broken by name (case-insensitive), matching legacy.
function M.getPlayersSortedByKills(session, handles, limit)
  local sorted = {}
  for _, handle in ipairs(handles) do
    sorted[#sorted + 1] = handle
  end

  table.sort(sorted, function(a, b)
    local killsA, killsB = getKills(session, a), getKills(session, b)
    if killsA ~= killsB then return killsA > killsB end
    return string.lower(session.player.name(a)) < string.lower(session.player.name(b))
  end)

  local limited = {}
  for i = 1, math.min(limit, #sorted) do
    limited[#limited + 1] = sorted[i]
  end
  return limited
end

function M.buildPlaceholders(session, handle)
  local placeholders = {}
  local mode = getWinMode(session)

  placeholders.alive = tostring(#session.alivePlayers())
  placeholders.spectators = tostring(#session.spectators())
  placeholders.kills = tostring(getKills(session, handle))
  placeholders.mode = getModeLabel(session, handle, mode)

  if mode == "most_kills" then
    local topPlayers = M.getPlayersSortedByKills(session, session.players(), 5)
    for i = 1, 5 do
      local placeKey = "place_" .. i
      local killsKey = "kills_" .. i
      local topHandle = topPlayers[i]
      if topHandle ~= nil then
        placeholders[placeKey] = session.player.name(topHandle)
        placeholders[killsKey] = tostring(getKills(session, topHandle))
      else
        placeholders[placeKey] = "-"
        placeholders[killsKey] = "0"
      end
    end
  end

  return placeholders
end

return M

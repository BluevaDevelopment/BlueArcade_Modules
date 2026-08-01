--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local statsService = require("support.stats_service")

local M = {}

function M.getWinMode(session)
  local mode = session.dataAccess.getGameDataString("basic.win_mode")
  if mode == nil then return "last_standing" end
  mode = string.lower(mode)
  if mode ~= "last_standing" and mode ~= "most_kills" then return "last_standing" end
  return mode
end

function M.getModeLabel(session, handle, mode)
  if mode == "most_kills" then
    return session.config.translation(handle, "scoreboard.mode_labels.most_kills")
  end
  return session.config.translation(handle, "scoreboard.mode_labels.last_standing")
end

function M.getScoreboardPath(session)
  return "scoreboard." .. M.getWinMode(session)
end

local function getKills(session, handle)
  return session.state.kills[handle] or 0
end

-- Sorted descending by kills, ties broken by name (case-insensitive) - same comparator as
-- `all_against_all`'s own leaderboard, matching `OutcomeService.getTopPlayersByKills` exactly.
function M.getTopPlayersByKills(session, handles, limit)
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

function M.awardWin(session, handle)
  if session.state.winnerId == nil then
    session.state.winnerId = handle
    statsService.recordWin(session, handle)
  end
end

return M

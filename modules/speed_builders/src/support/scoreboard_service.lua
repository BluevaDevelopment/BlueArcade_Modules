--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy SpeedBuildersScoreboardService.java.
local M = {}

local function formatCountdownTime(seconds)
  local safeSeconds = math.max(0, seconds)
  return string.format("%02d:%02d", math.floor(safeSeconds / 60), safeSeconds % 60)
end

local function formatPercentage(percentage)
  return string.format("%.0f%%", percentage or 0)
end
M.formatPercentage = formatPercentage

local function phaseKey(phase)
  if phase == "SHOWCASE" then
    return "scoreboard.showcase"
  elseif phase == "JUDGING" then
    return "scoreboard.judging"
  end
  return "scoreboard.build"
end

function M.update(session, state)
  local key = phaseKey(state.phase)
  for _, handle in ipairs(session.players()) do
    local placeholders = {
      arena = tostring(session.arenaId),
      round = tostring(state.currentRound),
      time = formatCountdownTime(state.timeLeft or 0),
      percentage = formatPercentage(state.lastScore[handle]),
    }
    session.scoreboard.show(handle, key)
    session.scoreboard.update(handle, key, placeholders)
  end
end

function M.getCustomPlaceholders(state, handle)
  return {
    round = tostring(state.currentRound or 0),
    time = formatCountdownTime(state.timeLeft or 0),
    percentage = formatPercentage(state.lastScore[handle]),
  }
end

return M

--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Lucky Pillars never schedules events (legacy's scheduledEvents list is always empty), so next_event/next_event_time always resolve to the "none" translations.
local M = {}

local function formatTime(seconds)
  local safeSeconds = math.max(0, seconds)
  return string.format("%02d:%02d", math.floor(safeSeconds / 60), safeSeconds % 60)
end

local function resolveNextEventLabel(session, handle)
  local none = session.config.translation(handle, "scoreboard.event.none")
  return none or ""
end

local function resolveNextEventTime(session, handle)
  local noneTime = session.config.translation(handle, "scoreboard.event.none_time")
  return noneTime or ""
end

local function resolveNextBlockTime(session, handle)
  local seconds = session.state.nextBlockDropAtClock and math.ceil(session.state.nextBlockDropAtClock - os.clock()) or -1
  if seconds < 0 then
    local noneTime = session.config.translation(handle, "scoreboard.event.none_time")
    return noneTime or ""
  end
  if seconds <= 0 then
    local now = session.config.translation(handle, "scoreboard.event.now")
    return now or ""
  end
  return formatTime(seconds)
end

function M.buildPlaceholders(session, handle, gameManager)
  local placeholders = {}
  placeholders.alive = tostring(#session.alivePlayers())
  placeholders.spectators = tostring(#session.spectators())
  placeholders.kills = tostring(gameManager.getPlayerKills(session, handle))
  placeholders.alive_teams = tostring(#gameManager.getAliveTeamIds(session))

  if session.teams.isEnabled() and not gameManager.isSoloMode(session) then
    local team = session.teams.forPlayer(handle)
    placeholders.team = team and team.displayName or "-"
  else
    local teamLabel = session.config.translation(handle, "scoreboard.solo_team_label")
    placeholders.team = teamLabel or ""
  end

  placeholders.next_event = resolveNextEventLabel(session, handle)
  placeholders.next_event_time = resolveNextEventTime(session, handle)
  placeholders.next_block_time = resolveNextBlockTime(session, handle)

  return placeholders
end

return M

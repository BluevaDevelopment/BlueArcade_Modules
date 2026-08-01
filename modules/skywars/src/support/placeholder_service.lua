--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy PlaceholderService.java.
local M = {}

local function formatTime(seconds)
  local safe = math.max(0, seconds)
  return string.format("%02d:%02d", math.floor(safe / 60), safe % 60)
end

local function resolveStormStatus(session, handle)
  local state = session.state
  if not state.stormActive or not state.stormCenter or state.stormRadius <= 0 then
    return session.config.translation(handle, "scoreboard.storm_status.safe") or ""
  end

  local loc = session.player.location(handle)
  local dx = loc.x - state.stormCenter.x
  local dz = loc.z - state.stormCenter.z
  local distanceSquared = (dx * dx) + (dz * dz)
  if distanceSquared <= state.stormRadius * state.stormRadius then
    return session.config.translation(handle, "scoreboard.storm_status.safe") or ""
  end
  return session.config.translation(handle, "scoreboard.storm_status.unsafe") or ""
end

local function resolveStormPhaseLabel(session, handle)
  if not session.state.stormActive then
    return session.config.translation(handle, "scoreboard.storm_phase.waiting") or ""
  end
  return session.config.translation(handle, "scoreboard.storm_phase.final") or ""
end

local function resolveNextEventLabel(session, handle)
  local event = session.state.nextEvent
  if not event or not event.label or event.label == "" then
    return session.config.translation(handle, "scoreboard.event.none") or ""
  end
  return event.label
end

local function resolveNextEventTime(session, handle)
  local event = session.state.nextEvent
  if not event then
    return session.config.translation(handle, "scoreboard.event.none_time") or ""
  end
  local seconds = event.triggerSeconds - session.state.matchSeconds
  if seconds < 0 then
    return session.config.translation(handle, "scoreboard.event.none_time") or ""
  end
  if seconds <= 0 then
    return session.config.translation(handle, "scoreboard.event.now") or ""
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
    placeholders.team = session.config.translation(handle, "scoreboard.solo_team_label") or ""
  end

  placeholders.storm_radius = tostring(math.ceil(session.state.stormRadius or 0))
  placeholders.storm_stage = resolveStormPhaseLabel(session, handle)
  placeholders.storm_status = resolveStormStatus(session, handle)
  placeholders.next_event = resolveNextEventLabel(session, handle)
  placeholders.next_event_time = resolveNextEventTime(session, handle)

  return placeholders
end

function M.getPlayersSortedByKills(session, gameManager, candidates, limit)
  local entries = {}
  for _, handle in ipairs(candidates) do
    entries[#entries + 1] = { handle = handle, kills = gameManager.getPlayerKills(session, handle) }
  end
  table.sort(entries, function(a, b)
    if a.kills ~= b.kills then
      return a.kills > b.kills
    end
    return session.player.name(a.handle):lower() < session.player.name(b.handle):lower()
  end)

  local ordered = {}
  for i, entry in ipairs(entries) do
    if i > limit then
      break
    end
    ordered[#ordered + 1] = entry.handle
  end
  return ordered
end

return M

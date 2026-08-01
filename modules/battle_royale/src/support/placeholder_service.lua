--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- resolveStormStatus skips legacy's world-equality guard - single world per arena, always true here.
local M = {}

local function resolveStormStatus(session, handle)
  if not session.state.stormCenter or session.state.stormRadius <= 0 then
    return session.config.translation(handle, "scoreboard.storm_status.safe")
  end

  local playerLoc = session.player.location(handle)
  local dx = playerLoc.x - session.state.stormCenter.x
  local dz = playerLoc.z - session.state.stormCenter.z
  local distanceSquared = dx * dx + dz * dz
  local radius = session.state.stormRadius
  if distanceSquared <= radius * radius then
    return session.config.translation(handle, "scoreboard.storm_status.safe")
  end
  return session.config.translation(handle, "scoreboard.storm_status.unsafe")
end

function M.buildPlaceholders(session, handle, gameManager)
  local placeholders = {}
  placeholders.alive = tostring(#session.alivePlayers())
  placeholders.spectators = tostring(#session.spectators())
  placeholders.kills = tostring(gameManager.getPlayerKills(session, handle))
  placeholders.alive_teams = tostring(#gameManager.getAliveTeamIds(session))

  if session.teams.isEnabled() then
    local team = session.teams.forPlayer(handle)
    placeholders.team = team and team.displayName or "-"
  else
    placeholders.team = session.config.translation(handle, "scoreboard.solo_team_label")
  end

  placeholders.storm_radius = tostring(math.ceil(session.state.stormRadius or 0))
  placeholders.storm_stage = tostring((session.state.stormStageIndex or 0) + 1)
  placeholders.storm_status = resolveStormStatus(session, handle)

  return placeholders
end

return M

-- Mirrors legacy SpeedBuildersSessionService.java.
local M = {}

function M.resetWorldDefaults(session)
  session.world.setTime(1000)
  session.world.setStorm(false)
  session.world.setThundering(false)
end

function M.resetPlayerStates(session)
  for _, handle in ipairs(session.players()) do
    session.player.setGameMode(handle, "SURVIVAL")
    session.player.resetTime(handle)
    session.player.resetWeather(handle)
    session.player.setAllowFlight(handle, false)
    session.player.setFlying(handle, false)
    session.player.resetMaxHealth(handle)
    session.player.setHealth(handle, math.min(session.player.health(handle), 20.0))
  end
end

function M.clearPlayerInventories(session)
  for _, handle in ipairs(session.players()) do
    session.player.clearInventory(handle)
    session.player.clearArmor(handle)
  end
end

function M.recordStats(session, state)
  for _, handle in ipairs(session.players()) do
    session.stats.add(handle, "games_played", 1)
    session.stats.add(handle, "rounds_survived", state.roundsSurvived[handle] or 0)
    session.stats.add(handle, "perfect_builds", state.perfectBuilds[handle] or 0)
  end
end

return M

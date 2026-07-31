-- Mirrors legacy GuessTheBuildCleanupService.java.
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
    session.player.resetMaxHealth(handle)
    session.player.setHealth(handle, math.min(session.player.health(handle), 20.0))
  end
end

function M.clearPlayerInventories(session)
  for _, handle in ipairs(session.players()) do
    session.player.clearInventory(handle)
    session.player.clearArmor(handle)
    -- No dedicated "clear off-hand" binding exists yet - reuses the same AIR-material convention
    -- getSlotItem/giveItem already treat as "empty" (see tnt_tag's own indicator restore).
    session.player.giveItem(handle, "AIR", 1, 40)
  end
end

return M

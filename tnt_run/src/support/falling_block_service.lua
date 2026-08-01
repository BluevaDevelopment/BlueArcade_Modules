--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local M = {}

function M.spawnFallingShard(session, location, materialName)
  local handle = session.world.spawnFallingBlock(location, materialName)
  if handle == nil then return end

  session.entities.setFallingBlockFlags(handle, false, false)

  local horizontalRandomness = session.config.getDouble("blocks.falling.horizontal_randomness", 0.08)
  local downwardVelocity = math.abs(session.config.getDouble("blocks.falling.downward_velocity", 0.3))
  local horizontalX = (math.random() * 2 - 1) * horizontalRandomness
  local horizontalZ = (math.random() * 2 - 1) * horizontalRandomness
  session.entities.setVelocity(handle, horizontalX, -downwardVelocity, horizontalZ)

  session.state.fallingBlocks[handle] = true
  session.scheduler.runLater("arena_" .. session.arenaId .. "_tnt_run_falling_" .. handle, function()
    if session.entities.isValid(handle) then
      session.entities.remove(handle)
    end
    session.state.fallingBlocks[handle] = nil
  end, 40)
end

function M.cleanupAll(session)
  for handle in pairs(session.state.fallingBlocks) do
    if session.entities.isValid(handle) then
      session.entities.remove(handle)
    end
  end
  session.state.fallingBlocks = {}
end

return M

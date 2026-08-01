-- Mirrors legacy BedWarsListener.onPlayerInteract: opens the real, live container inventory.
local M = {}

function M.openContainer(session, handle, x, y, z)
  return session.player.openRealContainer(handle, x, y, z)
end

return M

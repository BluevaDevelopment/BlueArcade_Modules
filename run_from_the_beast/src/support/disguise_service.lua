-- Mirrors legacy RunFromTheBeastDisguiseService.java - a real, non-player decoy mob that follows
-- the beast's location every tick while the real beast player is hidden from everyone but
-- themselves. Uses session.player.hideEntity/showEntity (real Player#hideEntity/showEntity,
-- Kotlin-side) and session.player.hidePlayer/showPlayer (real Player#hidePlayer/showPlayer) plus
-- the new session.entities.configureBeastDisguise composite for the decoy's own AI/gravity/
-- persistence flags. skinId is always "creeper" here (a hardcoded default) rather than the
-- store-selected skin legacy offers (creeper/villager/jeb sheep) - StoreAPI is entirely unbound in
-- this project's Lua layer, and unlike skywars' kit fallback there is no non-store default skin in
-- legacy's own config to fall back to, so this is a deliberate adaptation (not literal legacy
-- behavior) to keep the module's actual core mechanic - a hidden beast - working at all without a
-- real store integration, rather than leaving the beast permanently undisguised.
local M = {}

local ENTITY_TYPE_BY_SKIN = { creeper = "CREEPER", villager = "VILLAGER", jeb = "SHEEP" }

local function updateVisibility(session, beast, disguiseHandle)
  for _, viewer in ipairs(session.players()) do
    if viewer == beast then
      session.player.hideEntity(viewer, disguiseHandle)
    else
      session.player.hidePlayer(viewer, beast)
      session.player.showEntity(viewer, disguiseHandle)
    end
  end
end

function M.apply(session, beast, skinId)
  M.remove(session, beast)
  local entityType = ENTITY_TYPE_BY_SKIN[(skinId or "creeper"):lower()]
  if not entityType or not beast then
    return
  end

  local disguiseHandle = session.world.spawnEntity(session.player.location(beast), entityType)
  if not disguiseHandle then
    return
  end

  session.entities.configureBeastDisguise(disguiseHandle, skinId)
  session.state.beastDisguiseHandle = disguiseHandle
  updateVisibility(session, beast, disguiseHandle)

  local taskId = "arena_" .. session.arenaId .. "_rftb_disguise"
  session.scheduler.runTimer(taskId, function()
    if session.state.ended or not session.state.beastDisguiseHandle then
      M.remove(session, beast)
      session.scheduler.cancelTask(taskId)
      return
    end
    if not session.entities.isValid(session.state.beastDisguiseHandle) then
      M.remove(session, beast)
      return
    end
    session.entities.teleport(session.state.beastDisguiseHandle, session.player.location(beast))
    updateVisibility(session, beast, session.state.beastDisguiseHandle)
  end, 0, 1)
end

function M.remove(session, beast)
  session.scheduler.cancelTask("arena_" .. session.arenaId .. "_rftb_disguise")

  local disguiseHandle = session.state.beastDisguiseHandle
  if disguiseHandle then
    session.entities.remove(disguiseHandle)
  end

  if beast then
    for _, viewer in ipairs(session.players()) do
      session.player.showPlayer(viewer, beast)
    end
  end

  session.state.beastDisguiseHandle = nil
end

return M

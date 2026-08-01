-- skinId is always "creeper" (hardcoded), not legacy's store-selected skin - StoreAPI is unbound
-- and legacy has no non-store default, so this keeps the beast disguised at all.
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

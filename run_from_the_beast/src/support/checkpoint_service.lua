--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local M = {}

function M.getCheckpointSetMaterial(session)
  return (session.config.getString("checkpoints.items.set") or "NETHER_STAR"):upper()
end

function M.getCheckpointReturnMaterial(session)
  return (session.config.getString("checkpoints.items.return") or "ENDER_EYE"):upper()
end

function M.giveCheckpointItems(session, handle)
  local defaultUses = session.config.getInt("checkpoints.default_uses", 1)
  session.state.checkpointUses[handle] = defaultUses

  session.player.giveEnchantedItem(handle, M.getCheckpointSetMaterial(session), 1, -1, nil, nil, false,
    session.config.translation(handle, "messages.checkpoint_items.set_name"),
    session.config.translationList(handle, "messages.checkpoint_items.set_lore"))
  session.player.giveEnchantedItem(handle, M.getCheckpointReturnMaterial(session), 1, -1, nil, nil, false,
    session.config.translation(handle, "messages.checkpoint_items.return_name"),
    session.config.translationList(handle, "messages.checkpoint_items.return_lore"))
end

function M.handleCheckpointSet(session, handle)
  local uses = session.state.checkpointUses[handle] or 0
  if uses <= 0 then
    session.messages.sendRaw(handle, session.config.translation(handle, "messages.checkpoint.no_uses"))
    return
  end

  session.state.checkpoints[handle] = session.player.location(handle)
  session.state.checkpointUses[handle] = uses - 1
  local message = session.config.translation(handle, "messages.checkpoint.set")
  if message then
    session.messages.sendRaw(handle, message:gsub("{uses}", tostring(uses - 1)))
  end
end

function M.handleCheckpointReturn(session, handle)
  local checkpoint = session.state.checkpoints[handle]
  if not checkpoint then
    session.messages.sendRaw(handle, session.config.translation(handle, "messages.checkpoint.none"))
    return
  end

  session.player.teleport(handle, checkpoint)
  session.messages.sendRaw(handle, session.config.translation(handle, "messages.checkpoint.teleported"))
end

return M

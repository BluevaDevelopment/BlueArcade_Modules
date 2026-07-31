local M = {}

local function getWoolSlots(session)
  local rawSlots = session.config.getStringList("tagging.inventory_indicator.wool_slots")
  local slots = {}
  for _, entry in ipairs(rawSlots) do
    local n = tonumber(entry)
    if n ~= nil then slots[#slots + 1] = n end
  end
  if #slots == 0 then
    slots = { 3, 5 }
  end
  return slots
end

local function storeSlot(session, handle, slot)
  local stored = session.state.indicatorStoredSlots[handle]
  if stored == nil then
    stored = {}
    session.state.indicatorStoredSlots[handle] = stored
  end
  if stored[slot] ~= nil then return end
  local item = session.player.getSlotItem(handle, slot)
  stored[slot] = item or { material = "AIR", amount = 1 }
end

function M.applyIndicator(session, handle, blinkState)
  if not session.config.getBoolean("tagging.inventory_indicator.enabled", true) then return end

  local tntSlot = session.config.getInt("tagging.inventory_indicator.tnt_slot", 4)
  local primaryWool = session.config.getString("tagging.inventory_indicator.wool_primary") or "RED_WOOL"
  local secondaryWool = session.config.getString("tagging.inventory_indicator.wool_secondary") or "WHITE_WOOL"
  local woolMaterial = blinkState and primaryWool or secondaryWool

  storeSlot(session, handle, tntSlot)
  session.player.giveItem(handle, "TNT", 1, tntSlot)

  for _, slot in ipairs(getWoolSlots(session)) do
    storeSlot(session, handle, slot)
    session.player.giveItem(handle, woolMaterial, 1, slot)
  end

  if session.config.getBoolean("tagging.inventory_indicator.apply_helmet", false) then
    storeSlot(session, handle, 39)
    session.player.giveItem(handle, "TNT", 1, 39)
  end
end

function M.clearIndicator(session, handle)
  local stored = session.state.indicatorStoredSlots[handle]
  if stored == nil then return end

  for slot, item in pairs(stored) do
    session.player.giveItem(handle, item.material, item.amount, slot)
  end
  session.state.indicatorStoredSlots[handle] = nil
end

function M.clearAllIndicators(session)
  for handle in pairs(session.state.indicatorStoredSlots) do
    M.clearIndicator(session, handle)
  end
end

return M

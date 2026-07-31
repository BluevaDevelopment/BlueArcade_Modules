local M = {}

local function splitColon(text)
  local parts = {}
  for part in string.gmatch(text, "[^:]+") do
    parts[#parts + 1] = part
  end
  return parts
end

local function applyEffects(session, handle, path)
  local effects = session.config.getStringList(path)
  for _, effectString in ipairs(effects) do
    local parts = splitColon(effectString)
    if #parts >= 3 then
      session.player.addPotionEffect(handle, parts[1], tonumber(parts[2]), tonumber(parts[3]))
    end
  end
end

local function clearEffects(session, handle, path)
  local effects = session.config.getStringList(path)
  for _, effectString in ipairs(effects) do
    local parts = splitColon(effectString)
    if #parts >= 1 then
      session.player.removePotionEffect(handle, parts[1])
    end
  end
end

local function giveStartingItems(session, handle)
  local items = session.config.getStringList("items.starting_items")
  for _, itemString in ipairs(items) do
    local parts = splitColon(itemString)
    if #parts >= 2 then
      local slotNumber = -1
      if #parts >= 3 then slotNumber = tonumber(parts[3]) end
      session.player.giveItem(handle, parts[1], tonumber(parts[2]), slotNumber)
    end
  end
end

function M.applyTaggedEffects(session, handle)
  applyEffects(session, handle, "effects.tagged_effects")
end

function M.clearTaggedEffects(session, handle)
  clearEffects(session, handle, "effects.tagged_effects")
end

function M.applyUntaggedEffects(session, handle)
  applyEffects(session, handle, "effects.untagged_effects")
end

function M.clearUntaggedEffects(session, handle)
  clearEffects(session, handle, "effects.untagged_effects")
end

function M.clearTransitionEffects(session, handle)
  M.clearTaggedEffects(session, handle)
  M.clearUntaggedEffects(session, handle)
end

function M.applyTaggedState(session, handle)
  M.clearTransitionEffects(session, handle)
  applyEffects(session, handle, "effects.starting_effects")
  M.applyTaggedEffects(session, handle)
end

function M.applyUntaggedState(session, handle)
  M.clearTransitionEffects(session, handle)
  applyEffects(session, handle, "effects.starting_effects")
  M.applyUntaggedEffects(session, handle)
end

function M.prepareForStart(session, handle)
  session.player.setGameMode(handle, "SURVIVAL")
  session.player.setHealth(handle, session.player.maxHealth(handle))
  session.player.setFoodLevel(handle, 20)
  session.player.setSaturation(handle, 20.0)
  giveStartingItems(session, handle)
  applyEffects(session, handle, "effects.starting_effects")
  M.applyUntaggedEffects(session, handle)
end

return M

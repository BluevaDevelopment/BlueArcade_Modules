-- Mirrors legacy ShopNpcService.java. ShopNpcDefinition/ShopNpcType aren't separate files - plain
-- Lua tables ({npcId, type, x, y, z, entityHandle}) with type as "STORE"/"UPGRADE" strings, same
-- convention as every other converted module's state delegates.
local M = {}

local NPC_SCAN_LIMIT = 64

local function resolveDataBasePath(session, section)
  if session.dataAccess.hasGameData("game.play_area." .. section) then
    return "game.play_area." .. section
  end
  return "game." .. section
end

function M.loadNpcDefinitions(session)
  local definitions = {}
  local base = resolveDataBasePath(session, "npcs")

  local registryRaw = session.dataAccess.getGameDataString(base .. ".npc_registry")
    or session.dataAccess.getGameDataString("game.npc_registry")

  local ids, seen = {}, {}
  if registryRaw and registryRaw ~= "" then
    for id in registryRaw:gmatch("[^,]+") do
      local trimmed = id:match("^%s*(.-)%s*$")
      if trimmed ~= "" and not seen[trimmed] then
        seen[trimmed] = true
        ids[#ids + 1] = trimmed
      end
    end
  end

  if #ids == 0 then
    for i = 1, NPC_SCAN_LIMIT do
      if session.dataAccess.hasGameData(base .. "." .. i .. ".type") then
        ids[#ids + 1] = tostring(i)
      end
    end
  end

  for _, npcId in ipairs(ids) do
    local basePath = base .. "." .. npcId
    local typeRaw = session.dataAccess.getGameDataString(basePath .. ".type")
    if typeRaw == "STORE" or typeRaw == "UPGRADE" then
      local loc = session.dataAccess.getGameLocation(basePath .. ".location")
      if loc then
        definitions[#definitions + 1] = {
          npcId = npcId,
          key = npcId:lower(),
          type = typeRaw,
          x = loc.x, y = loc.y, z = loc.z,
          entityHandle = nil,
        }
      end
    end
  end

  return definitions
end

function M.spawnNpcs(session)
  for _, def in ipairs(session.state.npcs) do
    if not def.entityHandle then
      local handle = session.world.spawnEntity({ x = def.x, y = def.y, z = def.z }, "VILLAGER")
      if handle then
        session.entities.configureShopNpc(handle)
        def.entityHandle = handle

        local labelKey = def.type == "STORE" and "messages.npc.store_hologram" or "messages.npc.upgrade_hologram"
        local label = session.config.translation(nil, labelKey) or ("<white>" .. def.type .. "</white>")
        local holoLoc = { x = def.x, y = def.y + 2.5, z = def.z }
        local hologram = session.hologram.spawn(holoLoc, { label })
        if hologram then
          session.state.npcHolograms[def.key] = hologram
        end
      end
    end
  end
end

function M.despawnNpcs(session)
  for _, def in ipairs(session.state.npcs) do
    if def.entityHandle then
      session.entities.remove(def.entityHandle)
      def.entityHandle = nil
    end
    local hologram = session.state.npcHolograms[def.key]
    if hologram then
      session.hologram.delete(hologram)
      session.state.npcHolograms[def.key] = nil
    end
  end
end

function M.getNpcDefinitionByHandle(session, entityHandle)
  if not entityHandle then return nil end
  for _, def in ipairs(session.state.npcs) do
    if def.entityHandle == entityHandle then
      return def
    end
  end
  return nil
end

return M

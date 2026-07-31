-- Mirrors legacy WoolService.java + WoolDefinition.java + WoolState.java, plus the wool-related
-- slice of ArenaState.java (wool states/carriers/capturers/holograms live on session.state, a
-- plain table, matching the project's established "no separate arena-state object" convention).
-- WoolState.DROPPED is never actually assigned in the legacy source (confirmed dead enum value) -
-- only "SPAWNED"/"CARRIED"/"CAPTURED" are used here.
local M = {}

local WOOL_ID_SCAN_LIMIT = 128

local function isNumericId(raw)
  if not raw or raw == "" then
    return false
  end
  return raw:match("^%d+$") ~= nil
end

local function resolveWoolBasePath(session)
  if session.dataAccess.hasGameData("game.play_area.wool_registry") then
    return "game.play_area"
  end
  return "game"
end

local function parseTeamList(raw, exclude)
  local result = {}
  local seen = {}
  if raw and raw ~= "" then
    for entry in raw:gmatch("[^,]+") do
      local value = entry:lower():gsub("^%s+", ""):gsub("%s+$", "")
      if value ~= "" and value ~= exclude and not seen[value] then
        seen[value] = true
        result[#result + 1] = value
      end
    end
  end
  return result
end

function M.loadWoolDefinitions(session)
  local definitions = {}
  local basePath = resolveWoolBasePath(session)

  local ids = {}
  local seenIds = {}
  local registryRaw = session.dataAccess.getGameDataString(basePath .. ".wool_registry")
  if registryRaw and registryRaw ~= "" then
    for idRaw in registryRaw:gmatch("[^,]+") do
      local id = idRaw:lower():gsub("^%s+", ""):gsub("%s+$", "")
      if isNumericId(id) and not seenIds[id] then
        seenIds[id] = true
        ids[#ids + 1] = id
      end
    end
  end

  if #ids == 0 then
    for i = 1, WOOL_ID_SCAN_LIMIT do
      local id = tostring(i)
      local woolBase = basePath .. ".wools." .. id
      if session.dataAccess.hasGameData(woolBase .. ".owner_team") and session.dataAccess.getGameLocation(woolBase .. ".spawn") then
        ids[#ids + 1] = id
      end
    end
  end

  local defaultMaterial = session.config.getString("wools.default_material") or "WHITE_WOOL"

  for _, woolId in ipairs(ids) do
    local woolBase = basePath .. ".wools." .. woolId
    local ownerTeamId = session.dataAccess.getGameDataString(woolBase .. ".owner_team")
    if ownerTeamId and ownerTeamId ~= "" then
      ownerTeamId = ownerTeamId:lower()

      local captureTeamIds = parseTeamList(session.dataAccess.getGameDataString(woolBase .. ".capture_teams"), ownerTeamId)
      local legacyCaptureTeam = session.dataAccess.getGameDataString(woolBase .. ".capture_team")
      if legacyCaptureTeam and legacyCaptureTeam ~= "" then
        local normalized = legacyCaptureTeam:lower()
        local already = false
        for _, existing in ipairs(captureTeamIds) do
          if existing == normalized then
            already = true
            break
          end
        end
        if normalized ~= ownerTeamId and not already then
          captureTeamIds[#captureTeamIds + 1] = normalized
        end
      end

      local spawnLocation = session.dataAccess.getGameLocation(woolBase .. ".spawn")
      local captureLocation = session.dataAccess.getGameLocation(woolBase .. ".capture")
      if spawnLocation then
        local material = session.dataAccess.getGameDataString(woolBase .. ".material") or defaultMaterial
        definitions[#definitions + 1] = {
          key = woolId:lower(),
          woolId = woolId,
          ownerTeamId = ownerTeamId,
          captureTeamIds = captureTeamIds,
          spawnLocation = spawnLocation,
          captureLocation = captureLocation,
          material = material,
        }
      end
    end
  end

  return definitions
end

local function resolveTeamReference(session, teamReference)
  if not teamReference then
    return ""
  end
  local normalized = teamReference:lower():gsub("^%s+", ""):gsub("%s+$", "")
  if normalized == "" then
    return ""
  end
  if not session.teams.isEnabled() then
    return normalized
  end

  local teams = session.teams.all()
  for _, team in ipairs(teams) do
    if team.id and team.id:lower() == normalized then
      return team.id:lower()
    end
  end

  if isNumericId(normalized) then
    local index = tonumber(normalized)
    local indexed = teams[index]
    if indexed and indexed.id then
      return indexed.id:lower()
    end
  end

  return normalized
end
M.resolveTeamReference = resolveTeamReference

local function canTeamStealWool(session, def, playerTeamId)
  if not def or not playerTeamId or playerTeamId == "" then
    return false
  end
  local resolvedPlayerTeamId = resolveTeamReference(session, playerTeamId)
  local resolvedOwnerTeamId = resolveTeamReference(session, def.ownerTeamId)
  if resolvedOwnerTeamId == resolvedPlayerTeamId then
    return false
  end
  if #def.captureTeamIds == 0 then
    return true
  end
  for _, captureTeam in ipairs(def.captureTeamIds) do
    if resolveTeamReference(session, captureTeam) == resolvedPlayerTeamId then
      return true
    end
  end
  return false
end
M.canTeamStealWool = canTeamStealWool

local function isTeamAssignedToCaptureWool(session, def, normalizedTeamId)
  if not def or not normalizedTeamId or normalizedTeamId == "" or #def.captureTeamIds == 0 then
    return false
  end
  for _, captureTeam in ipairs(def.captureTeamIds) do
    if resolveTeamReference(session, captureTeam) == normalizedTeamId then
      return true
    end
  end
  return false
end
M.isTeamAssignedToCaptureWool = isTeamAssignedToCaptureWool

function M.getWoolState(session, woolKey)
  return session.state.woolStates[woolKey] or "SPAWNED"
end

local function locationsMatch(a, x, y, z)
  if not a then
    return false
  end
  return math.floor(a.x) == x and math.floor(a.y) == y and math.floor(a.z) == z
end

local function clearSpawnWoolVisuals(session, woolKey)
  local hologram = session.state.woolHolograms[woolKey]
  if hologram then
    session.hologram.delete(hologram)
    session.state.woolHolograms[woolKey] = nil
  end
end

local function keepWoolSpawnBlockAlive(session, def)
  local spawn = def.spawnLocation
  local x, y, z = math.floor(spawn.x), math.floor(spawn.y), math.floor(spawn.z)

  if session.world.blockTypeAt(x, y, z) ~= def.material then
    session.world.setBlockType(x, y, z, def.material)
  end

  if not session.state.woolHolograms[def.key] then
    local title = session.config.translation(nil, "messages.wool.break_hint.title") or "<yellow><bold>BREAK THIS WOOL</bold></yellow>"
    local subtitle = session.config.translation(nil, "messages.wool.break_hint.subtitle") or "<gray>Break it to carry it.</gray>"
    local hologramLoc = { x = x + 0.5, y = y + 1.8, z = z + 0.5 }
    local hologram = session.hologram.spawn(hologramLoc, { title, subtitle })
    if hologram then
      session.state.woolHolograms[def.key] = hologram
    end
  end
end

function M.spawnAllWools(session)
  for _, def in ipairs(session.state.woolDefinitions) do
    local state = M.getWoolState(session, def.key)
    if state == "CARRIED" and not session.state.woolCarriers[def.key] then
      state = "SPAWNED"
      session.state.woolStates[def.key] = "SPAWNED"
    end

    if state == "SPAWNED" then
      keepWoolSpawnBlockAlive(session, def)
    else
      clearSpawnWoolVisuals(session, def.key)
    end
  end
end

local function removeCarrierHologram(session, woolKey)
  local hologram = session.state.carrierHolograms[woolKey]
  if hologram then
    session.hologram.delete(hologram)
    session.state.carrierHolograms[woolKey] = nil
  end
end

local function resolveWoolColor(material)
  local name = material or ""
  if name:find("RED") then return "<red>" end
  if name:find("BLUE") and not name:find("LIGHT_BLUE") then return "<blue>" end
  if name:find("GREEN") then return "<green>" end
  if name:find("YELLOW") then return "<yellow>" end
  if name:find("ORANGE") then return "<gold>" end
  if name:find("PURPLE") and not name:find("LIGHT_PURPLE") then return "<dark_purple>" end
  if name:find("PINK") or name:find("MAGENTA") or name:find("LIGHT_PURPLE") then return "<light_purple>" end
  if name:find("CYAN") or name:find("LIGHT_BLUE") then return "<aqua>" end
  if name:find("BLACK") then return "<dark_gray>" end
  if name:find("GRAY") then return "<gray>" end
  if name:find("BROWN") then return "<gold>" end
  return "<white>"
end
M.resolveWoolColor = resolveWoolColor

local function spawnCarrierHologram(session, def, carrierHandle)
  removeCarrierHologram(session, def.key)

  local line = session.config.translation(carrierHandle, "messages.wool.carrier_hologram")
  if not line then
    line = resolveWoolColor(def.material) .. "⬛ CARRYING WOOL ⬛"
  end

  local loc = session.player.location(carrierHandle)
  local hologramLoc = { x = loc.x, y = loc.y + 2.5, z = loc.z }
  local hologram = session.hologram.spawn(hologramLoc, { line })
  if hologram then
    session.state.carrierHolograms[def.key] = hologram
  end
end

local function removeCarrierHologramsForPlayer(session, playerHandle)
  for _, def in ipairs(session.state.woolDefinitions) do
    if session.state.woolCarriers[def.key] == playerHandle then
      removeCarrierHologram(session, def.key)
    end
  end
end

function M.updateCarrierHolograms(session)
  for _, def in ipairs(session.state.woolDefinitions) do
    if M.getWoolState(session, def.key) == "CARRIED" then
      local carrierHandle = session.state.woolCarriers[def.key]
      local hologram = session.state.carrierHolograms[def.key]
      if carrierHandle and hologram then
        local loc = session.player.location(carrierHandle)
        if loc then
          session.hologram.teleport(hologram, { x = loc.x, y = loc.y + 2.5, z = loc.z })
        end
      end
    end
  end
end

local function oneWoolAtATimeEnabled(session)
  return session.config.getBoolean("game.one_wool_at_a_time", true)
end

function M.isPlayerCarryingWool(session, playerHandle)
  for _, def in ipairs(session.state.woolDefinitions) do
    if session.state.woolCarriers[def.key] == playerHandle then
      return true
    end
  end
  return false
end

function M.isCarriedWoolMaterial(session, playerHandle, material)
  for _, def in ipairs(session.state.woolDefinitions) do
    if session.state.woolCarriers[def.key] == playerHandle and def.material == material then
      return true
    end
  end
  return false
end

function M.isObjectiveWoolMaterial(session, material)
  for _, def in ipairs(session.state.woolDefinitions) do
    if def.material == material then
      return true
    end
  end
  return false
end

function M.clearTrackedWoolItems(session)
  for key, hologram in pairs(session.state.woolHolograms) do
    session.hologram.delete(hologram)
    session.state.woolHolograms[key] = nil
  end
  for key, hologram in pairs(session.state.carrierHolograms) do
    session.hologram.delete(hologram)
    session.state.carrierHolograms[key] = nil
  end
end

function M.isCaptureLocation(session, x, y, z)
  for _, def in ipairs(session.state.woolDefinitions) do
    if locationsMatch(def.captureLocation, x, y, z) then
      return true
    end
  end
  return false
end

function M.isWoolSpawnLocation(session, x, y, z)
  for _, def in ipairs(session.state.woolDefinitions) do
    if locationsMatch(def.spawnLocation, x, y, z) then
      return true
    end
  end
  return false
end

function M.handleWoolPickup(session, playerHandle, x, y, z)
  if not session.teams.isEnabled() then
    return false
  end
  local team = session.teams.forPlayer(playerHandle)
  if not team then
    return false
  end
  local playerTeamId = team.id:lower()

  for _, def in ipairs(session.state.woolDefinitions) do
    if locationsMatch(def.spawnLocation, x, y, z) then
      if M.getWoolState(session, def.key) ~= "SPAWNED" then
        return false
      end
      if not canTeamStealWool(session, def, playerTeamId) then
        return false
      end
      if oneWoolAtATimeEnabled(session) and M.isPlayerCarryingWool(session, playerHandle) then
        return false
      end

      session.world.setBlockType(x, y, z, "AIR")
      clearSpawnWoolVisuals(session, def.key)

      local itemName = "&6Wool &e#" .. def.woolId .. " &7(" .. def.ownerTeamId .. " -> " .. (def.captureTeamIds[1] or "") .. ")"
      session.player.giveEnchantedItem(playerHandle, def.material, 1, -1, nil, 1, false, itemName, nil)

      session.state.woolStates[def.key] = "CARRIED"
      session.state.woolCarriers[def.key] = playerHandle
      spawnCarrierHologram(session, def, playerHandle)

      local message = session.config.translation(playerHandle, "messages.wool.picked_up")
      if message then
        message = message:gsub("{player}", session.player.name(playerHandle))
          :gsub("{team}", resolveTeamReference(session, def.ownerTeamId))
          :gsub("{wool}", def.woolId)
        for _, p in ipairs(session.players()) do
          session.messages.sendRaw(p, message)
        end
      end
      for _, p in ipairs(session.players()) do
        session.sounds.playDirect(p, "ENTITY_ITEM_PICKUP", 1.0, 1.0)
      end

      return true
    end
  end
  return false
end

function M.resolveWoolPickupBlockedMessage(session, playerHandle, x, y, z)
  if not session.teams.isEnabled() then
    return nil
  end
  local team = session.teams.forPlayer(playerHandle)
  if not team then
    return nil
  end
  local playerTeamId = team.id:lower()

  for _, def in ipairs(session.state.woolDefinitions) do
    if locationsMatch(def.spawnLocation, x, y, z) then
      if M.getWoolState(session, def.key) ~= "SPAWNED" then
        return nil
      end

      if def.ownerTeamId == playerTeamId then
        local message = session.config.translation(playerHandle, "messages.wool.cannot_break_own")
          or "<red>This wool belongs to your team. You must defend it.</red>"
        return message:gsub("{team}", resolveTeamReference(session, def.ownerTeamId)):gsub("{wool}", def.woolId)
      end

      if not canTeamStealWool(session, def, playerTeamId) then
        local message = session.config.translation(playerHandle, "messages.wool.cannot_break")
          or "<red>You cannot break this wool.</red>"
        return message:gsub("{team}", resolveTeamReference(session, def.ownerTeamId)):gsub("{wool}", def.woolId)
      end

      if oneWoolAtATimeEnabled(session) and M.isPlayerCarryingWool(session, playerHandle) then
        return session.config.translation(playerHandle, "messages.wool.already_carrying")
          or "<red>You can only carry one wool at a time.</red>"
      end

      return nil
    end
  end
  return nil
end

function M.handleWoolCapture(session, playerHandle, x, y, z, placedMaterial)
  if not session.teams.isEnabled() then
    return false
  end
  local team = session.teams.forPlayer(playerHandle)
  if not team then
    return false
  end
  local playerTeamId = team.id:lower()

  for _, def in ipairs(session.state.woolDefinitions) do
    if locationsMatch(def.captureLocation, x, y, z) then
      local state = M.getWoolState(session, def.key)
      if state == "CAPTURED" then
        return false
      end

      local carrier = session.state.woolCarriers[def.key]
      if state ~= "CARRIED" or carrier ~= playerHandle then
        return false
      end
      if not canTeamStealWool(session, def, playerTeamId) then
        return false
      end
      if placedMaterial ~= def.material then
        return false
      end

      session.state.woolStates[def.key] = "CAPTURED"
      session.state.woolCarriers[def.key] = nil
      session.state.woolCapturers[def.key] = playerHandle

      removeCarrierHologram(session, def.key)

      local message = session.config.translation(playerHandle, "messages.wool.captured")
      if message then
        message = message:gsub("{player}", session.player.name(playerHandle))
          :gsub("{team}", resolveTeamReference(session, def.ownerTeamId))
          :gsub("{wool}", def.woolId)
        for _, p in ipairs(session.players()) do
          session.messages.sendRaw(p, message)
        end
      end
      for _, p in ipairs(session.players()) do
        session.sounds.playDirect(p, "ENTITY_PLAYER_LEVELUP", 1.0, 1.0)
      end

      return true
    end
  end
  return false
end

-- removeWoolItems isn't ported - legacy's own WoolService.handlePlayerDeath calls it, but the
-- caller (CombatService.handleElimination) always clears the player's entire inventory
-- immediately afterward, making it dead code in every real code path (confirmed by reading
-- both call sites) - see combat_service.lua's own inventory clear.
function M.handlePlayerDeath(session, playerHandle)
  removeCarrierHologramsForPlayer(session, playerHandle)

  local lostWool = false
  for _, def in ipairs(session.state.woolDefinitions) do
    if session.state.woolCarriers[def.key] == playerHandle then
      session.state.woolStates[def.key] = "SPAWNED"
      session.state.woolCarriers[def.key] = nil
      lostWool = true
      keepWoolSpawnBlockAlive(session, def)
    end
  end

  if lostWool then
    local message = session.config.translation(playerHandle, "messages.wool.dropped")
    if message then
      message = message:gsub("{player}", session.player.name(playerHandle))
      for _, p in ipairs(session.players()) do
        session.messages.sendRaw(p, message)
      end
    end
    for _, p in ipairs(session.players()) do
      session.sounds.playDirect(p, "BLOCK_NOTE_BLOCK_PLING", 1.0, 0.5)
    end
  end
end

function M.hasTeamCapturedAllWools(session, teamId)
  local normalizedTeamId = resolveTeamReference(session, teamId)
  local hasWools = false
  for _, def in ipairs(session.state.woolDefinitions) do
    if isTeamAssignedToCaptureWool(session, def, normalizedTeamId) then
      hasWools = true
      if M.getWoolState(session, def.key) ~= "CAPTURED" then
        return false
      end
    end
  end
  return hasWools
end

function M.getTeamObjectiveCount(session, teamId)
  local normalizedTeamId = resolveTeamReference(session, teamId)
  local count = 0
  for _, def in ipairs(session.state.woolDefinitions) do
    if isTeamAssignedToCaptureWool(session, def, normalizedTeamId) then
      count = count + 1
    end
  end
  return count
end

function M.getTeamCapturedObjectives(session, teamId)
  local normalizedTeamId = resolveTeamReference(session, teamId)
  local count = 0
  for _, def in ipairs(session.state.woolDefinitions) do
    if isTeamAssignedToCaptureWool(session, def, normalizedTeamId) and M.getWoolState(session, def.key) == "CAPTURED" then
      count = count + 1
    end
  end
  return count
end

function M.buildWoolStatusLine(session, teamId)
  local normalizedTeamId = resolveTeamReference(session, teamId)
  local parts = {}
  for _, def in ipairs(session.state.woolDefinitions) do
    if resolveTeamReference(session, def.ownerTeamId) == normalizedTeamId then
      local color = resolveWoolColor(def.material)
      local state = M.getWoolState(session, def.key)
      if state == "CAPTURED" then
        parts[#parts + 1] = color .. "█"
      elseif state == "CARRIED" then
        parts[#parts + 1] = color .. "░"
      else
        parts[#parts + 1] = color .. "⬜"
      end
    end
  end
  return table.concat(parts, " ")
end

return M

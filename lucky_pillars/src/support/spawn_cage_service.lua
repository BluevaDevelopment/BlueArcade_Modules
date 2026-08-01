-- storeAPI is always nil, so every cage uses cage.yml's default_cage (same as legacy's no-StoreAPI fallback). resolveCageOwners/resolveTeamCageOwners aren't ported - confirmed dead code (buildCages never calls them).
local M = {}

local MAX_DISTANCE_SQUARED = 2.25

local function squaredDistance(a, b)
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return dx * dx + dy * dy + dz * dz
end

-- Block-coordinate key (matches legacy ArenaState.toKey) - read and write must floor consistently or a caged spawn won't be recognised for a second player.
local function blockKey(location)
  return math.floor(location.x) .. ":" .. math.floor(location.y) .. ":" .. math.floor(location.z)
end

local function resolveCageDefinition(session)
  local cageId = session.config.getStringFrom("cage.yml", "default_cage", "clear_glass")
  local base = "cages." .. cageId
  local material = session.config.getStringFrom("cage.yml", base .. ".material", "GLASS")
  local headClear = session.config.getBooleanFrom("cage.yml", base .. ".head_clear", false)
  return { material = material, headClear = headClear }
end

local function resolveSpawnForPlayer(session, handle, spawns, playerLocation)
  if not session.arena.isInBounds(playerLocation) then
    return nil
  end
  if #spawns == 0 then
    return playerLocation
  end

  local closest, closestDistance = nil, math.huge
  for _, spawn in ipairs(spawns) do
    if not session.state.cagedSpawnKeys[blockKey(spawn)] then
      local distance = squaredDistance(spawn, playerLocation)
      if distance < closestDistance then
        closestDistance = distance
        closest = spawn
      end
    end
  end

  if not closest or closestDistance > MAX_DISTANCE_SQUARED then
    return nil
  end
  return closest
end

local function placeBlock(session, material, x, y, z)
  session.world.setBlockType(x, y, z, material)
  session.state.cageBlocks[#session.state.cageBlocks + 1] = { x = x, y = y, z = z }
end

local function markPlayersAtSpawn(session, baseLocation)
  session.state.cagedSpawnKeys[blockKey(baseLocation)] = true
  for _, handle in ipairs(session.players()) do
    if squaredDistance(session.player.location(handle), baseLocation) <= MAX_DISTANCE_SQUARED then
      session.state.cagedPlayers[handle] = true
    end
  end
end

function M.buildCages(session)
  local players = session.players()
  if #players == 0 then
    return
  end

  local spawns = {}
  for _, location in pairs(session.state.teamSpawns) do
    spawns[#spawns + 1] = location
  end

  local cage = resolveCageDefinition(session)

  for _, handle in ipairs(players) do
    if not session.state.cagedPlayers[handle] then
      local playerLocation = session.player.location(handle)
      local spawn = resolveSpawnForPlayer(session, handle, spawns, playerLocation)
      if spawn then
        local baseX = math.floor(playerLocation.x)
        local baseY = math.floor(playerLocation.y)
        local baseZ = math.floor(playerLocation.z)

        if session.arena.isInBounds(playerLocation) then
          placeBlock(session, cage.material, baseX, baseY - 1, baseZ)

          for y = 0, 2 do
            if not (cage.headClear and y == 1) then
              placeBlock(session, cage.material, baseX, baseY + y, baseZ + 1)
              placeBlock(session, cage.material, baseX, baseY + y, baseZ - 1)
              placeBlock(session, cage.material, baseX + 1, baseY + y, baseZ)
              placeBlock(session, cage.material, baseX - 1, baseY + y, baseZ)
            end
          end

          placeBlock(session, cage.material, baseX, baseY + 3, baseZ)

          markPlayersAtSpawn(session, { x = baseX, y = baseY, z = baseZ })
        end
      end
    end
  end
end

function M.removeCages(session)
  if #session.state.cageBlocks == 0 then
    return
  end

  for _, block in ipairs(session.state.cageBlocks) do
    session.world.setBlockType(block.x, block.y, block.z, "AIR")
  end

  session.state.cageBlocks = {}
  session.state.cagedPlayers = {}
  session.state.cagedSpawnKeys = {}
end

return M

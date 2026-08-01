-- Mirrors legacy SpawnCageService.java. CageDefinition is a plain {material, headClear} table.
-- StoreAPI-driven cage-skin selection is skipped (unbound); always uses `cage.yml`'s
-- `default_cage`. The arena-level `getSpawns()` fallback isn't ported - team spawns are always
-- required before a match can start, so it's unreachable.
local M = {}

function M.isEnabled(session)
  return session.config.getBoolean("cages.enabled", true)
end

local function resolveCageDefinition(session)
  local cageId = session.config.getStringFrom("cage.yml", "default_cage", "clear_glass")
  local base = "cages." .. cageId
  local materialName = session.config.getStringFrom("cage.yml", base .. ".material", "GLASS")
  local headClear = session.config.getBooleanFrom("cage.yml", base .. ".head_clear", false)
  return { material = materialName, headClear = headClear }
end

local function squaredDistance(a, b)
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return dx * dx + dy * dy + dz * dz
end

local function blockKey(x, y, z)
  return x .. ":" .. y .. ":" .. z
end

local function placeBlock(session, material, x, y, z)
  session.world.setBlockType(x, y, z, material)
  session.state.cageBlocks[blockKey(x, y, z)] = true
end

local function resolveSpawnForPlayer(session, handle)
  local playerLoc = session.player.location(handle)
  if not playerLoc then return nil end
  if not session.isInsideBounds(playerLoc) then return nil end

  local closest, closestDistance = nil, math.huge
  for _, spawn in pairs(session.state.teamSpawns) do
    if not session.state.cagedSpawns[blockKey(math.floor(spawn.x), math.floor(spawn.y), math.floor(spawn.z))] then
      local d = squaredDistance(spawn, playerLoc)
      if d < closestDistance then
        closestDistance = d
        closest = spawn
      end
    end
  end

  if not closest or closestDistance > 2.25 then
    return nil
  end
  return closest
end

local function markPlayersAtSpawn(session, spawn)
  session.state.cagedSpawns[blockKey(math.floor(spawn.x), math.floor(spawn.y), math.floor(spawn.z))] = true
  for _, handle in ipairs(session.players()) do
    local loc = session.player.location(handle)
    if loc and squaredDistance(loc, spawn) <= 2.25 then
      session.state.cagedPlayers[handle] = true
    end
  end
end

function M.buildCages(session)
  if not M.isEnabled(session) then return end

  local interiorRadius = 0
  local wallOffset = interiorRadius + 1
  local floorOffset = -1
  local roofOffset = 3
  local wallTopOffset = 2

  for _, handle in ipairs(session.players()) do
    if not session.state.cagedPlayers[handle] then
      local candidateSpawn = resolveSpawnForPlayer(session, handle)
      if candidateSpawn then
        local cage = resolveCageDefinition(session)
        local spawn = session.player.location(handle)
        if spawn and session.isInsideBounds(spawn) then
          local baseX, baseY, baseZ = math.floor(spawn.x), math.floor(spawn.y), math.floor(spawn.z)

          for x = -interiorRadius, interiorRadius do
            for z = -interiorRadius, interiorRadius do
              placeBlock(session, cage.material, baseX + x, baseY + floorOffset, baseZ + z)
            end
          end

          for y = 0, wallTopOffset do
            if not (cage.headClear and y == 1) then
              for x = -interiorRadius, interiorRadius do
                placeBlock(session, cage.material, baseX + x, baseY + y, baseZ + wallOffset)
                placeBlock(session, cage.material, baseX + x, baseY + y, baseZ - wallOffset)
              end
              for z = -interiorRadius, interiorRadius do
                placeBlock(session, cage.material, baseX + wallOffset, baseY + y, baseZ + z)
                placeBlock(session, cage.material, baseX - wallOffset, baseY + y, baseZ + z)
              end
            end
          end

          placeBlock(session, cage.material, baseX, baseY + roofOffset, baseZ)
          markPlayersAtSpawn(session, spawn)
        end
      end
    end
  end
end

function M.removeCages(session)
  local hasBlocks = false
  for _ in pairs(session.state.cageBlocks) do
    hasBlocks = true
    break
  end
  if not hasBlocks then return end

  for key in pairs(session.state.cageBlocks) do
    local x, y, z = key:match("^(-?%d+):(-?%d+):(-?%d+)$")
    if x then
      session.world.setBlockType(tonumber(x), tonumber(y), tonumber(z), "AIR")
    end
  end

  session.state.cageBlocks = {}
  session.state.cagedPlayers = {}
  session.state.cagedSpawns = {}
end

function M.getCagedPlayerCount(session)
  local count = 0
  for _ in pairs(session.state.cagedPlayers) do
    count = count + 1
  end
  return count
end

function M.scheduleSpawnCages(session)
  local taskId = "arena_" .. session.arenaId .. "_bed_wars_cages"
  local maxTicks = 40
  local ticks = 0
  session.scheduler.runTimer(taskId, function()
    M.buildCages(session)
    ticks = ticks + 1
    if ticks >= maxTicks or M.getCagedPlayerCount(session) >= #session.players() then
      session.scheduler.cancelTask(taskId)
    end
  end, 1, 1)
end

function M.scheduleCageGuard(session, teleportToTeamSpawn)
  local taskId = "arena_" .. session.arenaId .. "_bed_wars_cage_guard"
  session.scheduler.runTimer(taskId, function()
    if not session.teams.isEnabled() then return end
    for _, handle in ipairs(session.players()) do
      local team = session.teams.forPlayer(handle)
      if team then
        local spawn = session.state.teamSpawns[team.id:lower()]
        if spawn then
          local playerLoc = session.player.location(handle)
          if playerLoc and squaredDistance(playerLoc, spawn) > 2.25 then
            teleportToTeamSpawn(session, handle)
          end
        end
      end
    end
  end, 10, 10)
end

return M

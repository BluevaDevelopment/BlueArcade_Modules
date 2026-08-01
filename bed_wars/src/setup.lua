--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy BedWarsSetup.java + SetupSupport.java + BedWarsSpawnerSetupHandler.java +
-- BedWarsNpcSetupHandler.java (bed/spawner/npc/region/team subcommands).
local M = {}

local function setupMessage(key)
  local msg = ba.config.translation(nil, "setup_messages." .. key)
  return msg or ""
end

local function isNumber(value)
  local n = tonumber(value)
  return n ~= nil and n == math.floor(n)
end

local function isNumericId(raw)
  if not raw or raw == "" then
    return false
  end
  if not raw:match("^%d+$") then
    return false
  end
  return tonumber(raw) > 0
end

local function normalizeTeamId(raw)
  if not raw then
    return nil
  end
  local value = raw:lower()
  return isNumericId(value) and value or nil
end

local function isExistingTeam(ctx, teamId)
  local teamCount = ctx.data.getInt("teams.count", 0)
  if teamCount <= 0 then
    return false
  end
  for i = 1, teamCount do
    if tostring(i) == teamId then
      return true
    end
  end
  return false
end

local function sendTeamIdRangeMessage(ctx)
  local teamCount = ctx.data.getInt("teams.count", 0)
  local max = teamCount > 0 and tostring(teamCount) or "N"
  ctx.reply(setupMessage("team.numeric_ids_only"):gsub("{min}", "1"):gsub("{max}", max))
end

local function parseRegistry(raw)
  local seen = {}
  local ids = {}
  if raw and raw ~= "" then
    for idRaw in raw:gmatch("[^,]+") do
      local id = idRaw:match("^%s*(.-)%s*$")
      if id ~= "" and not seen[id] then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  return ids, seen
end

-- team --

local function handleTeamConfig(ctx)
  if ctx.argCount < 2 then
    ctx.reply(setupMessage("team.usage"))
    return
  end

  local setting = ctx.args[1]
  if setting ~= "count" and setting ~= "size" then
    ctx.reply(setupMessage("team.usage"))
    return
  end

  local valueRaw = ctx.args[2]
  if not isNumber(valueRaw) then
    ctx.reply(ctx.coreConfig.language("admin_commands.errors.invalid_number"):gsub("{value}", valueRaw or ""))
    return
  end

  local value = tonumber(valueRaw)
  if value <= 0 then
    ctx.reply(setupMessage("team.invalid_value"):gsub("{setting}", setting))
    return
  end
  if setting == "count" and value < 2 then
    ctx.reply(setupMessage("team.invalid_count"))
    return
  end
  if setting == "size" and value < 1 then
    ctx.reply(setupMessage("team.invalid_size"))
    return
  end

  local teamCount = ctx.data.getInt("teams.count", 0)
  local teamSize = ctx.data.getInt("teams.size", 0)
  if setting == "count" then
    teamCount = value
  else
    teamSize = value
  end

  local maxPlayers = ctx.data.getArenaInt("arena.basic.max_players", 0)
  if teamCount > 0 and teamSize > 0 and maxPlayers > 0 and teamCount * teamSize > maxPlayers then
    ctx.reply(setupMessage("team.invalid_limit"):gsub("{max_players}", tostring(maxPlayers)))
    return
  end

  ctx.data.setTeamConfig(teamCount, teamSize)
  ctx.data.save()

  ctx.reply(setupMessage("team.success")
    :gsub("{game}", ctx.gameId)
    :gsub("{arena_id}", tostring(ctx.arenaId))
    :gsub("{setting}", setting:lower())
    :gsub("{value}", tostring(value)))
end

local function handleTeamSpawn(ctx)
  if ctx.argCount < 2 then
    ctx.reply(setupMessage("team_spawn.usage"))
    return
  end

  local teamId = normalizeTeamId(ctx.args[2])
  if not teamId then
    ctx.reply(setupMessage("team_spawn.usage"))
    sendTeamIdRangeMessage(ctx)
    return
  end
  if not isExistingTeam(ctx, teamId) then
    sendTeamIdRangeMessage(ctx)
    return
  end
  if not ctx.isPlayer then
    return
  end

  ctx.data.setLocation("game.play_area.team_spawns." .. teamId, ctx.playerLocation)
  ctx.data.save()

  ctx.reply(setupMessage("team_spawn.set"):gsub("{team}", teamId))
end

local function handleTeam(ctx)
  if ctx.args[1] == "spawn" then
    handleTeamSpawn(ctx)
  else
    handleTeamConfig(ctx)
  end
end

-- bed --

local function handleBed(ctx)
  if ctx.argCount < 1 then
    ctx.reply(setupMessage("bed.usage"))
    return
  end

  local action = ctx.args[1]
  if action ~= "set" then
    ctx.reply(setupMessage("bed.usage"))
    return
  end

  if ctx.argCount < 2 then
    ctx.reply(setupMessage("bed.set_usage"))
    return
  end

  local teamId = normalizeTeamId(ctx.args[2])
  if not teamId then
    sendTeamIdRangeMessage(ctx)
    return
  end
  if not isExistingTeam(ctx, teamId) then
    sendTeamIdRangeMessage(ctx)
    return
  end
  if not ctx.isPlayer then
    return
  end

  local targetBlock = ctx.playerTargetBlock(5)
  if not targetBlock then
    ctx.reply(setupMessage("bed.must_look_at_block"))
    return
  end

  ctx.data.setLocation("game.play_area.beds." .. teamId, targetBlock)
  ctx.data.save()

  ctx.reply(setupMessage("bed.set"):gsub("{team}", teamId))
end

-- region --

local function handleRegion(ctx)
  if ctx.argCount < 1 then
    ctx.reply(setupMessage("region.usage"))
    return
  end

  local action = ctx.args[1]
  if action == "clear" then
    ctx.data.remove("game.play_area")
    ctx.data.remove("regeneration.regions")
    ctx.data.save()
    ctx.reply(setupMessage("region.cleared"))
    return
  end

  if action ~= "set" then
    ctx.reply(setupMessage("region.usage"))
    return
  end

  if not ctx.isPlayer then
    return
  end
  if not ctx.selection.hasCompleteSelection() then
    ctx.reply(setupMessage("region.must_use_stick"))
    return
  end

  local pos1 = ctx.selection.getPosition1()
  local pos2 = ctx.selection.getPosition2()

  ctx.data.registerRegenerationRegion("game.play_area", pos1, pos2)
  ctx.data.save()

  local x = math.abs(pos2.x - pos1.x) + 1
  local y = math.abs(pos2.y - pos1.y) + 1
  local z = math.abs(pos2.z - pos1.z) + 1
  local blocks = x * y * z

  ctx.reply(setupMessage("region.set")
    :gsub("{blocks}", tostring(blocks))
    :gsub("{x}", tostring(x))
    :gsub("{y}", tostring(y))
    :gsub("{z}", tostring(z)))
end

-- spawner --

local function handleSpawnerAdd(ctx)
  if ctx.argCount < 3 then
    ctx.reply(setupMessage("spawner.add_usage"))
    return
  end

  local typeUpper = ctx.args[2] and ctx.args[2]:upper() or ""
  if typeUpper ~= "IRON" and typeUpper ~= "GOLD" and typeUpper ~= "DIAMOND" and typeUpper ~= "EMERALD" then
    ctx.reply(setupMessage("spawner.invalid_type"):gsub("{type}", ctx.args[2] or ""))
    return
  end

  local hologramRaw = ctx.args[3]
  if not hologramRaw or (hologramRaw:lower() ~= "true" and hologramRaw:lower() ~= "false") then
    ctx.reply(setupMessage("spawner.invalid_hologram"):gsub("{value}", hologramRaw or ""))
    return
  end
  local hologram = hologramRaw:lower() == "true"

  if not ctx.isPlayer then
    return
  end

  local targetBlock = ctx.playerTargetBlock(5)
  if not targetBlock then
    ctx.reply(setupMessage("spawner.must_look_at_block"))
    return
  end

  local registry = parseRegistry(ctx.data.getString("game.play_area.spawner_registry"))
  local spawnerId = tostring(#registry + 1)
  registry[#registry + 1] = spawnerId

  local basePath = "game.play_area.spawners." .. spawnerId
  ctx.data.setString(basePath .. ".type", typeUpper)
  ctx.data.setLocation(basePath .. ".location", targetBlock)
  ctx.data.setString(basePath .. ".hologram", tostring(hologram))
  ctx.data.setString("game.play_area.spawner_registry", table.concat(registry, ","))
  ctx.data.save()

  ctx.reply(setupMessage("spawner.added")
    :gsub("{id}", spawnerId)
    :gsub("{type}", typeUpper)
    :gsub("{hologram}", tostring(hologram)))
end

local function handleSpawnerList(ctx)
  local registryRaw = ctx.data.getString("game.play_area.spawner_registry")
  local entries = parseRegistry(registryRaw)
  if #entries == 0 then
    ctx.reply(setupMessage("spawner.list_empty"))
    return
  end

  ctx.reply(setupMessage("spawner.list_header"))
  for _, spawnerId in ipairs(entries) do
    local basePath = "game.play_area.spawners." .. spawnerId
    local spawnerType = ctx.data.getString(basePath .. ".type")
    if spawnerType and spawnerType ~= "" then
      local hologram = ctx.data.getString(basePath .. ".hologram")
      ctx.reply(setupMessage("spawner.list_line")
        :gsub("{id}", spawnerId)
        :gsub("{type}", spawnerType)
        :gsub("{hologram}", hologram or "-"))
    end
  end
end

local function samePosition(pos1, pos2)
  return pos1 and pos2
    and math.floor(pos1.x) == math.floor(pos2.x)
    and math.floor(pos1.y) == math.floor(pos2.y)
    and math.floor(pos1.z) == math.floor(pos2.z)
end

local function handleSpawnerRemove(ctx)
  if not ctx.isPlayer then
    return
  end

  local targetBlock = ctx.playerTargetBlock(5)
  if not targetBlock then
    ctx.reply(setupMessage("spawner.must_look_at_block"))
    return
  end

  local registryRaw = ctx.data.getString("game.play_area.spawner_registry")
  if not registryRaw or registryRaw == "" then
    ctx.reply(setupMessage("spawner.not_found"))
    return
  end

  local registry = parseRegistry(registryRaw)
  local foundId = nil
  for _, spawnerId in ipairs(registry) do
    local loc = ctx.data.getLocation("game.play_area.spawners." .. spawnerId .. ".location")
    if samePosition(loc, targetBlock) then
      foundId = spawnerId
      break
    end
  end

  if not foundId then
    ctx.reply(setupMessage("spawner.not_found"))
    return
  end

  ctx.data.remove("game.play_area.spawners." .. foundId)
  local remaining = {}
  for _, spawnerId in ipairs(registry) do
    if spawnerId ~= foundId then
      remaining[#remaining + 1] = spawnerId
    end
  end
  ctx.data.setString("game.play_area.spawner_registry", table.concat(remaining, ","))
  ctx.data.save()

  ctx.reply(setupMessage("spawner.removed"):gsub("{id}", foundId))
end

local function handleSpawner(ctx)
  if ctx.argCount < 1 then
    ctx.reply(setupMessage("spawner.usage"))
    return
  end

  local action = ctx.args[1]
  if action == "list" then
    handleSpawnerList(ctx)
  elseif action == "remove" then
    handleSpawnerRemove(ctx)
  elseif action == "add" then
    handleSpawnerAdd(ctx)
  else
    ctx.reply(setupMessage("spawner.usage"))
  end
end

-- npc --

local function handleNpcAdd(ctx)
  if ctx.argCount < 2 then
    ctx.reply(setupMessage("npc.add_usage"))
    return
  end

  local typeUpper = ctx.args[2] and ctx.args[2]:upper() or ""
  if typeUpper ~= "STORE" and typeUpper ~= "UPGRADE" then
    ctx.reply(setupMessage("npc.invalid_type"):gsub("{type}", ctx.args[2] or ""))
    return
  end

  if not ctx.isPlayer then
    return
  end

  local registry = parseRegistry(ctx.data.getString("game.play_area.npc_registry"))
  local npcId = tostring(#registry + 1)
  registry[#registry + 1] = npcId

  local basePath = "game.play_area.npcs." .. npcId
  ctx.data.setString(basePath .. ".type", typeUpper)
  ctx.data.setLocation(basePath .. ".location", ctx.playerLocation)
  ctx.data.setString("game.play_area.npc_registry", table.concat(registry, ","))
  ctx.data.save()

  ctx.reply(setupMessage("npc.added"):gsub("{id}", npcId):gsub("{type}", typeUpper))
end

local function handleNpcList(ctx)
  local registryRaw = ctx.data.getString("game.play_area.npc_registry")
  local entries = parseRegistry(registryRaw)
  if #entries == 0 then
    ctx.reply(setupMessage("npc.list_empty"))
    return
  end

  ctx.reply(setupMessage("npc.list_header"))
  for _, npcId in ipairs(entries) do
    local npcType = ctx.data.getString("game.play_area.npcs." .. npcId .. ".type")
    if npcType and npcType ~= "" then
      ctx.reply(setupMessage("npc.list_line"):gsub("{id}", npcId):gsub("{type}", npcType))
    end
  end
end

local function handleNpcRemove(ctx)
  if ctx.argCount < 2 then
    ctx.reply(setupMessage("npc.remove_usage"))
    return
  end

  local npcId = ctx.args[2]
  local registryRaw = ctx.data.getString("game.play_area.npc_registry")
  local registry = parseRegistry(registryRaw)
  local exists = false
  for _, id in ipairs(registry) do
    if id == npcId then
      exists = true
      break
    end
  end
  if not exists then
    ctx.reply(setupMessage("npc.not_found"):gsub("{id}", npcId))
    return
  end

  ctx.data.remove("game.play_area.npcs." .. npcId)
  local remaining = {}
  for _, id in ipairs(registry) do
    if id ~= npcId then
      remaining[#remaining + 1] = id
    end
  end
  ctx.data.setString("game.play_area.npc_registry", table.concat(remaining, ","))
  ctx.data.save()

  ctx.reply(setupMessage("npc.removed"):gsub("{id}", npcId))
end

local function handleNpc(ctx)
  if ctx.argCount < 1 then
    ctx.reply(setupMessage("npc.usage"))
    return
  end

  local action = ctx.args[1]
  if action == "list" then
    handleNpcList(ctx)
  elseif action == "remove" then
    handleNpcRemove(ctx)
  elseif action == "add" then
    handleNpcAdd(ctx)
  else
    ctx.reply(setupMessage("npc.usage"))
  end
end

function M.register()
  ba.setup.on("team", handleTeam)
  ba.setup.on("bed", handleBed)
  ba.setup.on("region", handleRegion)
  ba.setup.on("spawner", handleSpawner)
  ba.setup.on("npc", handleNpc)

  ba.setup.status("team", function(ctx)
    return ctx.data.getInt("teams.count", 0) > 0 and ctx.data.getInt("teams.size", 0) > 0
  end)

  ba.setup.status("bed", function(ctx)
    local teamCount = ctx.data.getInt("teams.count", 0)
    if teamCount <= 0 then
      return false
    end
    for i = 1, teamCount do
      if not ctx.data.has("game.play_area.beds." .. tostring(i) .. ".x") then
        return false
      end
    end
    return true
  end)

  ba.setup.status("region", function(ctx)
    return ctx.data.has("game.play_area.bounds.min.x") and ctx.data.has("game.play_area.bounds.max.x")
  end)

  ba.setup.status("spawner", function(ctx)
    local raw = ctx.data.getString("game.play_area.spawner_registry")
    return raw ~= nil and raw ~= ""
  end)

  ba.setup.status("npc", function(ctx)
    local raw = ctx.data.getString("game.play_area.npc_registry")
    return raw ~= nil and raw ~= ""
  end)
end

return M

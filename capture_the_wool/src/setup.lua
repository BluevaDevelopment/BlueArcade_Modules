--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy CaptureTheWoolSetup.java. Unlike legacy, admin-typed material names aren't
-- validated here (no Lua binding checks Material.valueOf) - an invalid one is stored as-is and just never resolves later.
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

local function normalizeWoolId(raw)
  if not raw then
    return nil
  end
  local value = raw:lower()
  return isNumericId(value) and value or nil
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

local function samePosition(pos1, pos2)
  return pos1 and pos2
    and math.floor(pos1.x) == math.floor(pos2.x)
    and math.floor(pos1.y) == math.floor(pos2.y)
    and math.floor(pos1.z) == math.floor(pos2.z)
end

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
  if setting == "size" and value < 2 then
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

local function handleTeamSpawnRemove(ctx)
  if ctx.argCount < 3 then
    ctx.reply(setupMessage("team_spawn.usage_remove"))
    return
  end

  local teamCount = ctx.data.getInt("teams.count", 0)
  if teamCount <= 0 then
    ctx.reply(setupMessage("team_spawn.teams_not_configured"))
    return
  end

  local teamId = normalizeTeamId(ctx.args[3])
  if not teamId then
    ctx.reply(setupMessage("team_spawn.usage_remove"))
    sendTeamIdRangeMessage(ctx)
    return
  end
  if not isExistingTeam(ctx, teamId) then
    sendTeamIdRangeMessage(ctx)
    return
  end

  ctx.data.remove("game.play_area.team_spawns." .. teamId)
  ctx.data.save()

  ctx.reply(setupMessage("team_spawn.removed"):gsub("{team}", teamId))
end

local function handleTeamSpawn(ctx)
  if ctx.argCount < 2 then
    ctx.reply(setupMessage("team_spawn.usage"))
    ctx.reply(setupMessage("team_spawn.usage_remove"))
    return
  end

  local firstArg = ctx.args[2]
  if firstArg and firstArg:lower() == "remove" then
    handleTeamSpawnRemove(ctx)
    return
  end

  local teamId = normalizeTeamId(firstArg)
  if not teamId then
    ctx.reply(setupMessage("team_spawn.usage"))
    ctx.reply(setupMessage("team_spawn.usage_remove"))
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

local function handleTeamZoneList(ctx)
  ctx.reply(setupMessage("team_zone.list_header"))
  local teamCount = ctx.data.getInt("teams.count", 0)
  local listed = 0
  for team = 1, teamCount do
    local teamId = tostring(team)
    local basePath = "game.play_area.restricted_zones." .. teamId
    for index = 1, 64 do
      if ctx.data.has(basePath .. "." .. index .. ".min") then
        ctx.reply(setupMessage("team_zone.list_line"):gsub("{team}", teamId):gsub("{index}", tostring(index)))
        listed = listed + 1
      end
    end
  end
  if listed == 0 then
    ctx.reply(setupMessage("team_zone.list_empty"))
  end
end

local function handleTeamZone(ctx)
  if ctx.argCount < 2 then
    ctx.reply(setupMessage("team_zone.usage"))
    return
  end

  local actionOrTeam = ctx.args[2]
  local action = actionOrTeam and actionOrTeam:lower() or ""

  if action == "list" then
    handleTeamZoneList(ctx)
    return
  end

  if action == "delete" then
    if ctx.argCount < 4 then
      ctx.reply(setupMessage("team_zone.delete_usage"))
      return
    end
    local teamId = normalizeTeamId(ctx.args[3])
    local indexRaw = ctx.args[4]
    if not teamId or not isNumber(indexRaw) then
      ctx.reply(setupMessage("team_zone.delete_usage"))
      sendTeamIdRangeMessage(ctx)
      return
    end
    if not isExistingTeam(ctx, teamId) then
      sendTeamIdRangeMessage(ctx)
      return
    end
    local index = tonumber(indexRaw)
    local zonePath = "game.play_area.restricted_zones." .. teamId .. "." .. index
    if not ctx.data.has(zonePath .. ".min") then
      ctx.reply(setupMessage("team_zone.not_found"):gsub("{team}", teamId):gsub("{index}", tostring(index)))
      return
    end
    ctx.data.remove(zonePath)
    ctx.data.save()
    ctx.reply(setupMessage("team_zone.deleted"):gsub("{team}", teamId):gsub("{index}", tostring(index)))
    return
  end

  local teamArg = (action == "create") and ctx.args[3] or ctx.args[2]
  local teamId = normalizeTeamId(teamArg)
  if not teamId then
    ctx.reply(setupMessage("team_zone.create_usage"))
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
  if not ctx.selection.hasCompleteSelection() then
    ctx.reply(setupMessage("team_zone.must_use_stick"))
    return
  end

  local pos1 = ctx.selection.getPosition1()
  local pos2 = ctx.selection.getPosition2()

  local index = 1
  local basePath = "game.play_area.restricted_zones." .. teamId
  while ctx.data.has(basePath .. "." .. index .. ".min") do
    index = index + 1
  end

  ctx.data.setLocation(basePath .. "." .. index .. ".min", pos1)
  ctx.data.setLocation(basePath .. "." .. index .. ".max", pos2)
  ctx.data.save()

  ctx.reply(setupMessage("team_zone.set"):gsub("{team}", teamId):gsub("{index}", tostring(index)))
end

local function handleTeam(ctx)
  local sub = ctx.args[1]
  if sub == "spawn" then
    handleTeamSpawn(ctx)
  elseif sub == "zone" then
    handleTeamZone(ctx)
  else
    handleTeamConfig(ctx)
  end
end

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

local function parseRegistry(raw)
  local seen = {}
  local ids = {}
  if raw and raw ~= "" then
    for idRaw in raw:gmatch("[^,]+") do
      local id = normalizeWoolId(idRaw)
      if id and not seen[id] then
        seen[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  return ids, seen
end

local function handleWoolList(ctx)
  local registryRaw = ctx.data.getString("game.play_area.wool_registry") or ctx.data.getString("game.wool_registry")
  local entries = parseRegistry(registryRaw)
  if #entries == 0 then
    ctx.reply(setupMessage("wool.list_empty"))
    return
  end

  ctx.reply(setupMessage("wool.list_header"))
  for _, woolId in ipairs(entries) do
    local basePath = "game.play_area.wools." .. woolId
    local ownerTeam = ctx.data.getString(basePath .. ".owner_team")
    if not ownerTeam or ownerTeam == "" then
      basePath = "game.wools." .. woolId
      ownerTeam = ctx.data.getString(basePath .. ".owner_team")
    end
    if ownerTeam and ownerTeam ~= "" then
      local captureTeam = ctx.data.getString(basePath .. ".capture_teams") or ctx.data.getString(basePath .. ".capture_team")
      local material = ctx.data.getString(basePath .. ".material")
      ctx.reply(setupMessage("wool.list_line")
        :gsub("{team}", ownerTeam)
        :gsub("{wool}", woolId)
        :gsub("{capture_team}", captureTeam or "-")
        :gsub("{material}", material or "-"))
    end
  end
end

local function handleWoolCreate(ctx)
  if ctx.argCount < 4 then
    ctx.reply(setupMessage("wool.create_usage"))
    return
  end

  local woolId = normalizeWoolId(ctx.args[2])
  local materialName = ctx.args[3]
  local ownerTeam = normalizeTeamId(ctx.args[4])

  if not woolId or not materialName or not ownerTeam then
    ctx.reply(setupMessage("wool.create_usage"))
    sendTeamIdRangeMessage(ctx)
    return
  end
  if not isExistingTeam(ctx, ownerTeam) then
    sendTeamIdRangeMessage(ctx)
    return
  end
  if not ctx.isPlayer then
    return
  end
  if not ctx.selection.hasCompleteSelection() then
    ctx.reply(setupMessage("wool.must_use_stick"))
    return
  end

  local pos1 = ctx.selection.getPosition1()
  local pos2 = ctx.selection.getPosition2()
  if not samePosition(pos1, pos2) then
    ctx.reply(setupMessage("wool.single_block_only"))
    return
  end

  local material = materialName:upper()
  local basePath = "game.play_area.wools." .. woolId
  ctx.data.setString(basePath .. ".owner_team", ownerTeam)
  ctx.data.setString(basePath .. ".material", material)
  ctx.data.setLocation(basePath .. ".spawn", pos1)

  local registryRaw = ctx.data.getString("game.play_area.wool_registry") or ctx.data.getString("game.wool_registry")
  local registry, seen = parseRegistry(registryRaw)
  if not seen[woolId] then
    registry[#registry + 1] = woolId
  end
  ctx.data.setString("game.play_area.wool_registry", table.concat(registry, ","))
  ctx.data.save()

  ctx.reply(setupMessage("wool.created")
    :gsub("{wool}", woolId)
    :gsub("{material}", material)
    :gsub("{team}", ownerTeam))
end

local function handleWoolClearCapture(ctx)
  if ctx.argCount < 2 then
    ctx.reply(setupMessage("wool.clear_capture_usage"))
    return
  end
  local woolId = normalizeWoolId(ctx.args[2])
  if not woolId then
    ctx.reply(setupMessage("wool.clear_capture_usage"))
    return
  end

  local basePath = "game.play_area.wools." .. woolId
  if not normalizeTeamId(ctx.data.getString(basePath .. ".owner_team")) then
    ctx.reply(setupMessage("wool.not_found"):gsub("{wool}", woolId))
    return
  end

  ctx.data.remove(basePath .. ".capture_team")
  ctx.data.remove(basePath .. ".capture_teams")
  ctx.data.remove(basePath .. ".capture")
  ctx.data.save()

  ctx.reply(setupMessage("wool.capture_cleared"):gsub("{wool}", woolId))
end

local function handleWoolCapture(ctx)
  if ctx.argCount < 3 then
    ctx.reply(setupMessage("wool.capture_usage"))
    return
  end

  local woolId = normalizeWoolId(ctx.args[2])
  local captureTeam = normalizeTeamId(ctx.args[3])
  if not woolId or not captureTeam then
    ctx.reply(setupMessage("wool.capture_usage"))
    sendTeamIdRangeMessage(ctx)
    return
  end

  local basePath = "game.play_area.wools." .. woolId
  local ownerTeam = normalizeTeamId(ctx.data.getString(basePath .. ".owner_team"))
  if not ownerTeam then
    ctx.reply(setupMessage("wool.not_found"):gsub("{wool}", woolId))
    return
  end
  if not isExistingTeam(ctx, captureTeam) then
    sendTeamIdRangeMessage(ctx)
    return
  end
  if ownerTeam == captureTeam then
    ctx.reply(setupMessage("wool.capture_owner_forbidden"):gsub("{wool}", woolId):gsub("{team}", ownerTeam))
    return
  end
  if not ctx.isPlayer then
    return
  end
  if not ctx.selection.hasCompleteSelection() then
    ctx.reply(setupMessage("wool.must_use_stick"))
    return
  end

  local pos1 = ctx.selection.getPosition1()
  local pos2 = ctx.selection.getPosition2()
  if not samePosition(pos1, pos2) then
    ctx.reply(setupMessage("wool.single_block_only"))
    return
  end

  local captureTeams, seen = parseRegistry(nil)
  local existingRaw = ctx.data.getString(basePath .. ".capture_teams")
  if existingRaw and existingRaw ~= "" then
    for idRaw in existingRaw:gmatch("[^,]+") do
      local id = normalizeTeamId(idRaw)
      if id and not seen[id] then
        seen[id] = true
        captureTeams[#captureTeams + 1] = id
      end
    end
  end
  local legacyCaptureTeam = normalizeTeamId(ctx.data.getString(basePath .. ".capture_team"))
  if legacyCaptureTeam and not seen[legacyCaptureTeam] then
    seen[legacyCaptureTeam] = true
    captureTeams[#captureTeams + 1] = legacyCaptureTeam
  end
  if not seen[captureTeam] then
    captureTeams[#captureTeams + 1] = captureTeam
  end

  ctx.data.setString(basePath .. ".capture_team", captureTeam)
  ctx.data.setString(basePath .. ".capture_teams", table.concat(captureTeams, ","))
  ctx.data.setLocation(basePath .. ".capture", pos1)
  ctx.data.save()

  ctx.reply(setupMessage("wool.capture_set")
    :gsub("{owner_team}", ownerTeam)
    :gsub("{capture_team}", table.concat(captureTeams, ","))
    :gsub("{wool}", woolId))
end

local function handleWool(ctx)
  if ctx.argCount < 1 then
    ctx.reply(setupMessage("wool.usage"))
    return
  end

  local action = ctx.args[1] and ctx.args[1]:lower() or nil
  if action == "list" then
    handleWoolList(ctx)
  elseif action == "create" then
    handleWoolCreate(ctx)
  elseif action == "clearcapture" then
    handleWoolClearCapture(ctx)
  elseif action == "capture" then
    handleWoolCapture(ctx)
  else
    ctx.reply(setupMessage("wool.usage"))
  end
end

function M.register()
  ba.setup.on("team", handleTeam)
  ba.setup.on("region", handleRegion)
  ba.setup.on("wool", handleWool)

  ba.setup.status("team", function(ctx)
    return ctx.data.getInt("teams.count", 0) > 0 and ctx.data.getInt("teams.size", 0) > 0
  end)

  ba.setup.status("region", function(ctx)
    return (ctx.data.has("game.play_area.bounds.min.x") and ctx.data.has("game.play_area.bounds.max.x"))
      or (ctx.data.has("game.region.bounds.min.x") and ctx.data.has("game.region.bounds.max.x"))
  end)

  ba.setup.status("wool", function(ctx)
    return ctx.data.has("game.play_area.wool_registry")
  end)
end

return M

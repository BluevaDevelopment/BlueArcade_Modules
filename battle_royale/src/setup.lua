--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local M = {}

local function setupMessage(key)
  local msg = ba.config.translation(nil, "setup_messages." .. key)
  return msg or ""
end

local function isNumber(value)
  local n = tonumber(value)
  return n ~= nil and n == math.floor(n)
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

function M.register()
  ba.setup.on("team", handleTeamConfig)
  ba.setup.on("region", handleRegion)

  ba.setup.status("team", function(ctx)
    return ctx.data.getInt("teams.count", 0) > 0 and ctx.data.getInt("teams.size", 0) > 0
  end)

  ba.setup.status("region", function(ctx)
    return (ctx.data.has("game.play_area.bounds.min.x") and ctx.data.has("game.play_area.bounds.max.x"))
      or (ctx.data.has("game.region.bounds.min.x") and ctx.data.has("game.region.bounds.max.x"))
  end)
end

return M

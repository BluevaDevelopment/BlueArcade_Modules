-- Mirrors legacy RunFromTheBeastSetup.java.
local M = {}

local function msg(ctx, key)
  local message = ba.config.translation(nil, "setup_messages." .. key)
  return message or ""
end

local function handleBeastSpawn(ctx)
  local action = ctx.args[1]
  if not action or action:lower() ~= "set" then
    ctx.reply(msg(ctx, "usage_beast_spawn"))
    return true
  end

  ctx.data.setLocation("game.beast.spawn", ctx.playerLocation)
  ctx.data.save()

  ctx.reply(msg(ctx, "beast_spawn_set"))
  return true
end

local function handleBeastZone(ctx)
  local action = ctx.args[1]
  if not action or action:lower() ~= "set" then
    ctx.reply(msg(ctx, "usage_beast_zone"))
    return true
  end

  if not ctx.selection.hasCompleteSelection() then
    ctx.reply(msg(ctx, "must_use_stick"))
    return true
  end

  local pos1 = ctx.selection.getPosition1()
  local pos2 = ctx.selection.getPosition2()

  ctx.data.setRegionBounds("game.beast_cage.bounds", pos1, pos2)
  ctx.data.saveRegionBlocks("game.beast_cage.blocks", pos1, pos2)
  ctx.data.save()

  local x = math.abs(pos2.x - pos1.x) + 1
  local y = math.abs(pos2.y - pos1.y) + 1
  local z = math.abs(pos2.z - pos1.z) + 1
  local blocks = x * y * z

  ctx.reply(msg(ctx, "beast_zone_set")
    :gsub("{blocks}", tostring(blocks))
    :gsub("{x}", tostring(x))
    :gsub("{y}", tostring(y))
    :gsub("{z}", tostring(z)))
  return true
end

function M.register()
  ba.setup.on("beastspawn", handleBeastSpawn)
  ba.setup.on("beastzone", handleBeastZone)

  ba.setup.status("beastspawn", function(ctx)
    return ctx.data.has("game.beast.spawn.x")
  end)

  ba.setup.status("beastzone", function(ctx)
    return ctx.data.has("game.beast_cage.bounds.min.x") and ctx.data.has("game.beast_cage.bounds.max.x")
  end)
end

return M

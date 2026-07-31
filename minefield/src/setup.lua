local M = {}

local function handleRegionSet(ctx, dataPath, usageKey, successKey)
  if not ctx.isPlayer then
    ctx.reply(ctx.coreConfig.language("admin_commands.errors.must_be_player"))
    return
  end

  if ctx.argCount < 1 then
    ctx.reply(ba.config.translation(ctx.player, usageKey))
    return
  end

  local action = string.lower(ctx.args[1])
  if action ~= "set" then
    ctx.reply(ba.config.translation(ctx.player, usageKey))
    return
  end

  if not ctx.selection.hasCompleteSelection() then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.must_use_stick"))
    return
  end

  local pos1 = ctx.selection.getPosition1()
  local pos2 = ctx.selection.getPosition2()

  ctx.data.setRegionBounds(dataPath, pos1, pos2)
  ctx.data.save()

  local x = math.floor(math.abs(pos2.x - pos1.x)) + 1
  local y = math.floor(math.abs(pos2.y - pos1.y)) + 1
  local z = math.floor(math.abs(pos2.z - pos1.z)) + 1
  local blocks = x * y * z

  local message = string.gsub(ba.config.translation(ctx.player, successKey), "{blocks}", tostring(blocks))
  message = string.gsub(message, "{x}", tostring(x))
  message = string.gsub(message, "{y}", tostring(y))
  message = string.gsub(message, "{z}", tostring(z))
  ctx.reply(message)
end

function M.register()
  ba.setup.on("finishline", function(ctx)
    handleRegionSet(ctx, "game.finish_line.bounds", "setup_messages.usage_finish_line", "setup_messages.set_success")
  end)

  ba.setup.on("floor", function(ctx)
    handleRegionSet(ctx, "game.floor.bounds", "setup_messages.usage_floor", "setup_messages.set_success_floor")
  end)

  ba.setup.status("finishline", function(ctx)
    return ctx.data.has("game.finish_line.bounds.min.x") and ctx.data.has("game.finish_line.bounds.max.x")
  end)

  ba.setup.status("floor", function(ctx)
    return ctx.data.has("game.floor.bounds.min.x") and ctx.data.has("game.floor.bounds.max.x")
  end)
end

return M

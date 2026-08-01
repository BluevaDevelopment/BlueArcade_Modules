local M = {}

function M.register()
  ba.setup.on("region", function(ctx)
    if not ctx.isPlayer then
      ctx.reply(ctx.coreConfig.language("admin_commands.errors.must_be_player"))
      return
    end

    if ctx.argCount < 1 then
      ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_region"))
      return
    end

    local action = string.lower(ctx.args[1])
    if action ~= "set" then
      ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_region"))
      return
    end

    if not ctx.selection.hasCompleteSelection() then
      ctx.reply(ba.config.translation(ctx.player, "setup_messages.must_use_stick"))
      return
    end

    local pos1 = ctx.selection.getPosition1()
    local pos2 = ctx.selection.getPosition2()

    ctx.data.registerRegenerationRegion("game.region", pos1, pos2)
    ctx.data.save()

    local x = math.floor(math.abs(pos2.x - pos1.x)) + 1
    local y = math.floor(math.abs(pos2.y - pos1.y)) + 1
    local z = math.floor(math.abs(pos2.z - pos1.z)) + 1
    local blocks = x * y * z

    local message = string.gsub(ba.config.translation(ctx.player, "setup_messages.set_success"), "{blocks}", tostring(blocks))
    message = string.gsub(message, "{x}", tostring(x))
    message = string.gsub(message, "{y}", tostring(y))
    message = string.gsub(message, "{z}", tostring(z))
    ctx.reply(message)
  end)

  -- Matches legacy: also checks "game.play_area.bounds" even though this module's own region
  -- handler never writes it.
  ba.setup.status("region", function(ctx)
    return (ctx.data.has("game.play_area.bounds.min.x") and ctx.data.has("game.play_area.bounds.max.x"))
        or (ctx.data.has("game.region.bounds.min.x") and ctx.data.has("game.region.bounds.max.x"))
  end)
end

return M

local M = {}

function M.register()
  ba.setup.on("setmode", function(ctx)
    if ctx.argCount < 1 then
      ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_setmode"))
      return
    end

    local mode = string.lower(ctx.args[1])
    if mode ~= "last_standing" and mode ~= "most_kills" then
      ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_setmode"))
      return
    end

    ctx.data.setString("basic.win_mode", mode)
    ctx.data.save()

    local message = string.gsub(ba.config.translation(ctx.player, "setup_messages.mode_set"), "{mode}", mode)
    ctx.reply(message)
  end)

  -- Unlike `all_against_all`'s own "setregion" (`registerRegenerationRegion` - a destructible
  -- floor), this module's play area is a static bounds check only, matching `fast_zone`/`race`/
  -- `traffic_light`/`minefield`'s own `setRegionBounds` pattern.
  ba.setup.on("setregion", function(ctx)
    if not ctx.selection.hasCompleteSelection() then
      ctx.reply(ba.config.translation(ctx.player, "setup_messages.must_use_stick"))
      return
    end

    local pos1 = ctx.selection.getPosition1()
    local pos2 = ctx.selection.getPosition2()

    ctx.data.setRegionBounds("game.play_area.bounds", pos1, pos2)
    ctx.data.save()

    local x = math.floor(math.abs(pos2.x - pos1.x)) + 1
    local y = math.floor(math.abs(pos2.y - pos1.y)) + 1
    local z = math.floor(math.abs(pos2.z - pos1.z)) + 1
    local blocks = x * y * z

    local message = string.gsub(ba.config.translation(ctx.player, "setup_messages.region_set"), "{blocks}", tostring(blocks))
    message = string.gsub(message, "{x}", tostring(x))
    message = string.gsub(message, "{y}", tostring(y))
    message = string.gsub(message, "{z}", tostring(z))
    ctx.reply(message)
  end)

  -- Checks both keys, matching `OneInTheChamberModule.getSetupMetadata`'s own status check
  -- exactly - "basic.mode" is never written by this module's own `setmode` handler (only
  -- "basic.win_mode" is), but the legacy check still ORs it in.
  ba.setup.status("setmode", function(ctx)
    return ctx.data.has("basic.win_mode") or ctx.data.has("basic.mode")
  end)

  ba.setup.status("setregion", function(ctx)
    return ctx.data.has("game.play_area.bounds.min.x") and ctx.data.has("game.play_area.bounds.max.x")
  end)
end

return M

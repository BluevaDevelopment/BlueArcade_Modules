--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local M = {}

function M.register()
  ba.setup.on("floor", function(ctx)
    if not ctx.isPlayer then
      ctx.reply(ctx.coreConfig.language("admin_commands.errors.must_be_player"))
      return
    end

    if ctx.argCount < 1 then
      ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_floor"))
      return
    end

    local action = string.lower(ctx.args[1])
    if action ~= "set" then
      ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_floor"))
      return
    end

    if not ctx.selection.hasCompleteSelection() then
      ctx.reply(ba.config.translation(ctx.player, "setup_messages.must_use_stick"))
      return
    end

    local pos1 = ctx.selection.getPosition1()
    local pos2 = ctx.selection.getPosition2()

    ctx.data.registerRegenerationRegion("game.floor", pos1, pos2)
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

  ba.setup.on("setmode", function(ctx)
    if ctx.argCount < 1 then
      ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_setmode"))
      return
    end

    local mode = string.lower(ctx.args[1])
    if mode ~= "chaos" and mode ~= "trail" then
      ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_setmode"))
      return
    end

    ctx.data.setString("basic.mode", mode)
    ctx.data.save()

    local message = string.gsub(ba.config.translation(ctx.player, "setup_messages.mode_set"), "{mode}", mode)
    ctx.reply(message)
  end)

  ba.setup.status("floor", function(ctx)
    return ctx.data.has("game.floor.bounds.min.x") and ctx.data.has("game.floor.bounds.max.x")
  end)

  -- Checks both keys, matching legacy's getSetupMetadata - "basic.win_mode" is never actually
  -- written by setmode, but legacy still ORs it in.
  ba.setup.status("setmode", function(ctx)
    return ctx.data.has("basic.win_mode") or ctx.data.has("basic.mode")
  end)
end

return M

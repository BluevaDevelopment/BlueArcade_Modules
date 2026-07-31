local VALID_MODES = { last_standing = true, most_kills = true }

local M = {}

function M.register()
  ba.setup.on("setmode", function(ctx)
    if ctx.argCount < 1 then
      ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_setmode"))
      return
    end

    local mode = string.lower(ctx.args[1])
    if not VALID_MODES[mode] then
      ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_setmode"))
      return
    end

    ctx.data.setString("basic.win_mode", mode)
    ctx.data.save()

    local message = string.gsub(ba.config.translation(ctx.player, "setup_messages.mode_set"), "{mode}", mode)
    ctx.reply(message)
  end)

  ba.setup.status("setmode", function(ctx)
    return ctx.data.has("basic.win_mode")
  end)
end

return M

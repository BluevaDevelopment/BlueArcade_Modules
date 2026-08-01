--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local M = {}

local function handleTime(ctx, path, usageKey)
  local usage = ba.config.translation(ctx.player, usageKey)

  if ctx.argCount < 1 then
    ctx.reply(usage)
    return
  end

  local value = tonumber(ctx.args[1])
  if value == nil or value <= 0 then
    ctx.reply(usage)
    return
  end

  ctx.data.setDouble(path, value)
  ctx.data.save()

  local message = string.gsub(ba.config.translation(ctx.player, "setup_messages.time_updated"), "{key}", path)
  message = string.gsub(message, "{value}", ctx.args[1])
  ctx.reply(message)
end

function M.register()
  ba.setup.on("musictime", function(ctx)
    handleTime(ctx, "basic.initial_music_time", "setup_messages.usage_music_time")
  end)
  ba.setup.on("sittime", function(ctx)
    handleTime(ctx, "basic.initial_sit_time", "setup_messages.usage_sit_time")
  end)
  ba.setup.on("musicreduction", function(ctx)
    handleTime(ctx, "basic.music_time_reduction", "setup_messages.usage_music_reduction")
  end)
  ba.setup.on("sitreduction", function(ctx)
    handleTime(ctx, "basic.sit_time_reduction", "setup_messages.usage_sit_reduction")
  end)

  ba.setup.status("musictime", function(ctx)
    return ctx.data.getDouble("basic.initial_music_time", 0) > 0
  end)
  ba.setup.status("sittime", function(ctx)
    return ctx.data.getDouble("basic.initial_sit_time", 0) > 0
  end)
  ba.setup.status("musicreduction", function(ctx)
    return ctx.data.getDouble("basic.music_time_reduction", 0) > 0
  end)
  ba.setup.status("sitreduction", function(ctx)
    return ctx.data.getDouble("basic.sit_time_reduction", 0) > 0
  end)
end

return M

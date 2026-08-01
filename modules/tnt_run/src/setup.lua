--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local M = {}

local MAX_FLOOR_SCAN = 100

local function resolveFloorTotal(data)
  local total = data.getInt("game.floors.total", 0)
  if total > 0 then return total end
  local last = 0
  for i = 1, MAX_FLOOR_SCAN do
    if data.has("game.floors.f" .. i .. ".bounds.min.x") then last = i end
  end
  return last
end

local function findLastFloor(data, currentTotal)
  for i = currentTotal - 1, 1, -1 do
    if data.has("game.floors.f" .. i .. ".bounds.min.x") then return i end
  end
  return 0
end

local function resolveBlockCount(data, floorKey)
  local min = data.getLocation("game.floors." .. floorKey .. ".bounds.min")
  local max = data.getLocation("game.floors." .. floorKey .. ".bounds.max")
  if min == nil or max == nil then return 0 end
  local x = math.floor(math.abs(max.x - min.x)) + 1
  local y = math.floor(math.abs(max.y - min.y)) + 1
  local z = math.floor(math.abs(max.z - min.z)) + 1
  return x * y * z
end

local function handleFloorAdd(ctx)
  if not ctx.isPlayer then
    ctx.reply(ctx.coreConfig.language("admin_commands.errors.must_be_player"))
    return
  end

  if not ctx.selection.hasCompleteSelection() then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.must_use_stick"))
    return
  end

  local pos1 = ctx.selection.getPosition1()
  local pos2 = ctx.selection.getPosition2()

  local total = resolveFloorTotal(ctx.data)
  local nextFloor = total + 1
  local floorKey = "f" .. nextFloor

  ctx.data.registerRegenerationRegion("game.floors." .. floorKey, pos1, pos2)
  ctx.data.setInt("game.floors." .. floorKey .. ".auto_remove_time", ba.config.getInt("floors.default_auto_remove_seconds", 0))
  ctx.data.setInt("game.floors.total", nextFloor)
  ctx.data.save()

  local x = math.floor(math.abs(pos2.x - pos1.x)) + 1
  local y = math.floor(math.abs(pos2.y - pos1.y)) + 1
  local z = math.floor(math.abs(pos2.z - pos1.z)) + 1
  local blocks = x * y * z

  local message = string.gsub(ba.config.translation(ctx.player, "setup_messages.floor_add_success"), "{number}", tostring(nextFloor))
  message = string.gsub(message, "{blocks}", tostring(blocks))
  ctx.reply(message)
end

local function handleFloorRemove(ctx)
  if ctx.argCount < 2 then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_floor_remove"))
    return
  end

  local floorNumber = tonumber(ctx.args[2])
  if floorNumber == nil then
    ctx.reply(string.gsub(ctx.coreConfig.language("admin_commands.errors.invalid_number"), "{value}", ctx.args[2]))
    return
  end

  local floorKey = "f" .. floorNumber
  if not ctx.data.has("game.floors." .. floorKey .. ".bounds.min.x") then
    ctx.reply(string.gsub(ba.config.translation(ctx.player, "setup_messages.floor_remove_not_found"), "{number}", tostring(floorNumber)))
    return
  end

  ctx.data.remove("game.floors." .. floorKey)

  local total = resolveFloorTotal(ctx.data)
  if floorNumber >= total then
    ctx.data.setInt("game.floors.total", findLastFloor(ctx.data, total))
  end
  ctx.data.save()

  ctx.reply(string.gsub(ba.config.translation(ctx.player, "setup_messages.floor_remove_success"), "{number}", tostring(floorNumber)))
end

local function handleFloorList(ctx)
  local total = resolveFloorTotal(ctx.data)
  if total == 0 then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.floor_list_empty"))
    return
  end

  ctx.reply(string.gsub(ba.config.translation(ctx.player, "setup_messages.floor_list_header"), "{arena_id}", tostring(ctx.arenaId)))

  for i = 1, total do
    local floorKey = "f" .. i
    if ctx.data.has("game.floors." .. floorKey .. ".bounds.min.x") then
      local autoRemoveTime = ctx.data.getInt("game.floors." .. floorKey .. ".auto_remove_time", 0)
      local blocks = resolveBlockCount(ctx.data, floorKey)
      local autoRemoveLabel
      if autoRemoveTime > 0 then
        autoRemoveLabel = autoRemoveTime .. "s"
      else
        autoRemoveLabel = ba.config.translation(ctx.player, "setup_messages.floor_list_disabled")
      end

      local message = string.gsub(ba.config.translation(ctx.player, "setup_messages.floor_list_item"), "{number}", tostring(i))
      message = string.gsub(message, "{blocks}", tostring(blocks))
      message = string.gsub(message, "{auto_remove}", autoRemoveLabel)
      ctx.reply(message)
    end
  end
end

local function handleFloorDelay(ctx)
  if ctx.argCount < 2 then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_floor_delay"))
    return
  end

  local ticks = tonumber(ctx.args[2])
  if ticks == nil then
    ctx.reply(string.gsub(ctx.coreConfig.language("admin_commands.errors.invalid_number"), "{value}", ctx.args[2]))
    return
  end

  local minTicks = ba.config.getInt("trail.floor_delay_limits.min", 1)
  local maxTicks = ba.config.getInt("trail.floor_delay_limits.max", 100)
  if ticks < minTicks or ticks > maxTicks then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.floor_delay_invalid"))
    return
  end

  ctx.data.setInt("basic.floor_delay", ticks)
  ctx.data.save()

  ctx.reply(string.gsub(ba.config.translation(ctx.player, "setup_messages.floor_delay_success"), "{ticks}", tostring(ticks)))
end

local function handleFloorRemoval(ctx)
  if ctx.argCount < 3 then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_floor_removal"))
    return
  end

  local floorNum = tonumber(ctx.args[2])
  local seconds = tonumber(ctx.args[3])
  if floorNum == nil or seconds == nil then
    ctx.reply(ctx.coreConfig.language("admin_commands.errors.invalid_number"))
    return
  end

  local maxSeconds = ba.config.getInt("floors.auto_remove_max_seconds", 600)
  if seconds < 0 or seconds > maxSeconds then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.floor_removal_invalid"))
    return
  end

  local floorKey = "f" .. floorNum
  if not ctx.data.has("game.floors." .. floorKey .. ".bounds.min.x") then
    ctx.reply(string.gsub(ba.config.translation(ctx.player, "setup_messages.floor_remove_not_found"), "{number}", tostring(floorNum)))
    return
  end

  ctx.data.setInt("game.floors." .. floorKey .. ".auto_remove_time", seconds)
  ctx.data.save()

  local key = seconds == 0 and "setup_messages.floor_removal_disabled" or "setup_messages.floor_removal_success"
  local message = string.gsub(ba.config.translation(ctx.player, key), "{floor}", tostring(floorNum))
  message = string.gsub(message, "{seconds}", tostring(seconds))
  ctx.reply(message)
end

local function handleDoubleJumpSet(ctx)
  if ctx.argCount < 2 then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_doublejump_set"))
    return
  end

  local amount = tonumber(ctx.args[2])
  if amount == nil then
    ctx.reply(string.gsub(ctx.coreConfig.language("admin_commands.errors.invalid_number"), "{value}", ctx.args[2]))
    return
  end

  local maxUses = ba.config.getInt("double_jump.max_uses", 10)
  if amount < 0 or amount > maxUses then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.doublejump_invalid"))
    return
  end

  ctx.data.setInt("basic.double_jump_uses", amount)
  ctx.data.save()

  local key = amount == 0 and "setup_messages.doublejump_disabled" or "setup_messages.doublejump_success"
  ctx.reply(string.gsub(ba.config.translation(ctx.player, key), "{amount}", tostring(amount)))
end

local function handleDoubleJumpBoost(ctx)
  if ctx.argCount < 3 then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_doublejump_boost"))
    return
  end

  local jumpType = string.lower(ctx.args[2])
  if jumpType ~= "vertical" and jumpType ~= "horizontal" then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.doublejump_boost_type_invalid"))
    return
  end

  local value = tonumber(ctx.args[3])
  if value == nil then
    ctx.reply(string.gsub(ctx.coreConfig.language("admin_commands.errors.invalid_number"), "{value}", ctx.args[3]))
    return
  end

  local minValue = ba.config.getDouble("double_jump.boost_limits.min", 0.1)
  local maxValue = ba.config.getDouble("double_jump.boost_limits.max", 2.0)
  if value < minValue or value > maxValue then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.doublejump_boost_invalid"))
    return
  end

  local configPath = jumpType == "vertical" and "basic.double_jump_vertical_boost" or "basic.double_jump_horizontal_boost"
  ctx.data.setDouble(configPath, value)
  ctx.data.save()

  local message = string.gsub(ba.config.translation(ctx.player, "setup_messages.doublejump_boost_success"), "{type}", jumpType)
  message = string.gsub(message, "{value}", tostring(value))
  ctx.reply(message)
end

function M.register()
  ba.setup.on("floor", function(ctx)
    if ctx.argCount < 1 then
      ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_floor"))
      return
    end

    local action = string.lower(ctx.args[1])
    if action == "add" then
      handleFloorAdd(ctx)
    elseif action == "remove" then
      handleFloorRemove(ctx)
    elseif action == "list" then
      handleFloorList(ctx)
    elseif action == "delay" then
      handleFloorDelay(ctx)
    elseif action == "removal" then
      handleFloorRemoval(ctx)
    else
      ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_floor"))
    end
  end)

  ba.setup.on("doublejump", function(ctx)
    if ctx.argCount < 2 then
      ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_doublejump"))
      return
    end

    local action = string.lower(ctx.args[1])
    if action == "set" then
      handleDoubleJumpSet(ctx)
    elseif action == "setboost" then
      handleDoubleJumpBoost(ctx)
    else
      ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_doublejump"))
    end
  end)

  ba.setup.status("floor", function(ctx)
    return resolveFloorTotal(ctx.data) > 0
  end)

  ba.setup.status("doublejump", function(ctx)
    return ctx.data.getInt("basic.double_jump_uses", -1) >= 0
  end)
end

return M

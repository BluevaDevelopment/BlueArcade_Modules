--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local generator = require("support.procedural_pattern_generator")

local M = {}

local function parseIndex(index)
  local names = {}
  if index == nil or index == "" then return names end
  for part in index:gmatch("[^,]+") do
    local trimmed = part:match("^%s*(.-)%s*$")
    if trimmed ~= "" then names[#names + 1] = trimmed end
  end
  return names
end

local function saveIndex(ctx, names)
  if #names == 0 then
    ctx.data.setString("game.patterns.index", "")
  else
    ctx.data.setString("game.patterns.index", table.concat(names, ","))
  end
end

local function generateNextPatternName(existing)
  local maxNumber = 0
  for _, entry in ipairs(existing) do
    local n = tonumber(entry)
    if n ~= nil then maxNumber = math.max(maxNumber, n) end
  end
  return tostring(maxNumber + 1)
end

local function createBlockList(ctx, pos1, pos2)
  local blocks = {}
  local minX, maxX = math.min(pos1.x, pos2.x), math.max(pos1.x, pos2.x)
  local minY, maxY = math.min(pos1.y, pos2.y), math.max(pos1.y, pos2.y)
  local minZ, maxZ = math.min(pos1.z, pos2.z), math.max(pos1.z, pos2.z)

  for x = math.floor(minX), math.floor(maxX) do
    for y = math.floor(minY), math.floor(maxY) do
      for z = math.floor(minZ), math.floor(maxZ) do
        local material = ctx.world.blockTypeAt(x, y, z)
        if material ~= nil and material ~= "AIR" and material ~= "BARRIER" then
          blocks[#blocks + 1] = "world," .. x .. "," .. y .. "," .. z .. "," .. material
        end
      end
    end
  end

  return blocks
end

local function handleFloor(ctx)
  if not ctx.isPlayer then
    ctx.reply(ctx.coreConfig.language("admin_commands.errors.must_be_player"))
    return
  end
  if ctx.argCount < 1 then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_floor"))
    return
  end
  if string.lower(ctx.args[1]) ~= "set" then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_floor"))
    return
  end

  if not ctx.selection.hasCompleteSelection() then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.must_use_stick"))
    return
  end

  local pos1 = ctx.selection.getPosition1()
  local pos2 = ctx.selection.getPosition2()

  ctx.data.setRegionBounds("game.floor.bounds", pos1, pos2)
  ctx.data.remove("game.floor.blocks")
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
end

local function handlePatternAdd(ctx)
  if not ctx.isPlayer then
    ctx.reply(ctx.coreConfig.language("admin_commands.errors.must_be_player"))
    return
  end

  local index = parseIndex(ctx.data.getString("game.patterns.index"))

  local name
  if ctx.argCount >= 2 then
    name = string.lower(ctx.args[2])
  else
    name = generateNextPatternName(index)
  end

  for _, existing in ipairs(index) do
    if existing == name then
      ctx.reply(string.gsub(ba.config.translation(ctx.player, "setup_messages.pattern_exists"), "{name}", name))
      return
    end
  end

  if not ctx.selection.hasCompleteSelection() then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.must_use_stick"))
    return
  end

  local pos1 = ctx.selection.getPosition1()
  local pos2 = ctx.selection.getPosition2()

  local blockList = createBlockList(ctx, pos1, pos2)
  ctx.data.setStringList("game.patterns." .. name, blockList)
  index[#index + 1] = name
  saveIndex(ctx, index)
  if ctx.data.getString("game.patterns.initial") == nil then
    ctx.data.setString("game.patterns.initial", name)
  end
  ctx.data.save()

  local x = math.floor(math.abs(pos2.x - pos1.x)) + 1
  local y = math.floor(math.abs(pos2.y - pos1.y)) + 1
  local z = math.floor(math.abs(pos2.z - pos1.z)) + 1
  local blocks = x * y * z

  local message = string.gsub(ba.config.translation(ctx.player, "setup_messages.pattern_added"), "{name}", name)
  message = string.gsub(message, "{blocks}", tostring(blocks))
  ctx.reply(message)
end

local function handlePatternRemove(ctx)
  if ctx.argCount < 2 then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_pattern_remove"))
    return
  end

  local name = string.lower(ctx.args[2])
  local index = parseIndex(ctx.data.getString("game.patterns.index"))
  local found = false
  local remaining = {}
  for _, existing in ipairs(index) do
    if existing == name then found = true else remaining[#remaining + 1] = existing end
  end
  if not found then
    ctx.reply(string.gsub(ba.config.translation(ctx.player, "setup_messages.pattern_missing"), "{name}", name))
    return
  end

  ctx.data.remove("game.patterns." .. name)
  saveIndex(ctx, remaining)
  local initial = ctx.data.getString("game.patterns.initial")
  if initial ~= nil and initial:lower() == name then
    ctx.data.setString("game.patterns.initial", remaining[1] or "")
  end
  ctx.data.save()

  ctx.reply(string.gsub(ba.config.translation(ctx.player, "setup_messages.pattern_removed"), "{name}", name))
end

local function handlePatternList(ctx)
  local index = parseIndex(ctx.data.getString("game.patterns.index"))
  if #index == 0 then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.pattern_required"))
    return
  end

  ctx.reply(ba.config.translation(ctx.player, "setup_messages.pattern_list_header"))
  for _, name in ipairs(index) do
    ctx.reply(string.gsub(ba.config.translation(ctx.player, "setup_messages.pattern_list_entry"), "{name}", name))
  end
end

local function handlePatternInitial(ctx)
  if ctx.argCount < 2 then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_pattern_initial"))
    return
  end

  local name = string.lower(ctx.args[2])
  local index = parseIndex(ctx.data.getString("game.patterns.index"))
  local found = false
  for _, existing in ipairs(index) do if existing == name then found = true break end end
  if not found then
    ctx.reply(string.gsub(ba.config.translation(ctx.player, "setup_messages.pattern_missing"), "{name}", name))
    return
  end

  ctx.data.setString("game.patterns.initial", name)
  ctx.data.save()
  ctx.reply(string.gsub(ba.config.translation(ctx.player, "setup_messages.pattern_initial_set"), "{name}", name))
end

local function handlePatternType(ctx)
  if ctx.argCount < 2 then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_pattern_type"))
    return
  end

  local patternType = string.lower(ctx.args[2])
  if patternType ~= "static" and patternType ~= "procedural" then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_pattern_type"))
    return
  end

  ctx.data.setString("game.pattern.type", patternType)
  ctx.data.save()
  if patternType == "procedural" then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.pattern_type_set_procedural"))
  else
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.pattern_type_set_static"))
  end
end

local function handlePatternStatus(ctx)
  local patternType = ctx.data.getString("game.pattern.type")
  if patternType == nil or patternType == "" then patternType = "not set" end
  local templates = ctx.data.getString("game.pattern.templates")
  if templates == nil or templates == "" then templates = "all" end

  local message = string.gsub(ba.config.translation(ctx.player, "setup_messages.pattern_type_status"), "{type}", patternType)
  message = string.gsub(message, "{templates}", templates)
  ctx.reply(message)
end

local function handlePatternTemplates(ctx)
  if ctx.argCount < 2 then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_pattern_templates"))
    return
  end

  local templates = {}
  local useAll = false
  for i = 2, ctx.argCount do
    for value in ctx.args[i]:gmatch("[^,]+") do
      local template = string.lower(value:match("^%s*(.-)%s*$"))
      if template == "all" then
        useAll = true
      elseif template ~= "" then
        local valid = false
        for _, known in ipairs(generator.TEMPLATE_TYPES) do if known == template then valid = true break end end
        local already = false
        for _, t in ipairs(templates) do if t == template then already = true break end end
        if valid and not already then templates[#templates + 1] = template end
      end
    end
    if useAll then break end
  end

  if useAll then
    ctx.data.remove("game.pattern.templates")
    ctx.data.save()
    ctx.reply(string.gsub(ba.config.translation(ctx.player, "setup_messages.pattern_templates_updated"), "{templates}", "all"))
    return
  end

  if #templates == 0 then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.pattern_templates_invalid"))
    return
  end

  ctx.data.setString("game.pattern.templates", table.concat(templates, ","))
  ctx.data.save()
  ctx.reply(string.gsub(ba.config.translation(ctx.player, "setup_messages.pattern_templates_updated"), "{templates}", table.concat(templates, ", ")))
end

local function handlePattern(ctx)
  if ctx.argCount < 1 then
    ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_pattern"))
    return
  end

  local action = string.lower(ctx.args[1])
  if action == "add" then handlePatternAdd(ctx)
  elseif action == "remove" then handlePatternRemove(ctx)
  elseif action == "list" then handlePatternList(ctx)
  elseif action == "initial" then handlePatternInitial(ctx)
  elseif action == "type" then handlePatternType(ctx)
  elseif action == "status" then handlePatternStatus(ctx)
  elseif action == "templates" then handlePatternTemplates(ctx)
  else ctx.reply(ba.config.translation(ctx.player, "setup_messages.usage_pattern"))
  end
end

local function handleTime(ctx, path, usageKey)
  if ctx.argCount < 1 then
    ctx.reply(ba.config.translation(ctx.player, usageKey))
    return
  end

  local value = tonumber(ctx.args[1])
  if value == nil then
    ctx.reply(ba.config.translation(ctx.player, usageKey))
    return
  end

  ctx.data.setDouble(path, value)
  ctx.data.save()

  local message = string.gsub(ba.config.translation(ctx.player, "setup_messages.time_updated"), "{key}", path)
  message = string.gsub(message, "{value}", ctx.args[1])
  ctx.reply(message)
end

function M.register()
  ba.setup.on("floor", handleFloor)
  ba.setup.on("pattern", handlePattern)
  ba.setup.on("musictime", function(ctx) handleTime(ctx, "basic.initial_music_time", "setup_messages.usage_music_time") end)
  ba.setup.on("searchtime", function(ctx) handleTime(ctx, "basic.search_time", "setup_messages.usage_search_time") end)
  ba.setup.on("decreasetime", function(ctx) handleTime(ctx, "basic.decrease_time", "setup_messages.usage_decrease_time") end)
  ba.setup.on("mintime", function(ctx) handleTime(ctx, "basic.min_search_time", "setup_messages.usage_min_time") end)

  ba.setup.status("floor", function(ctx)
    return ctx.data.has("game.floor.bounds.min.x") and ctx.data.has("game.floor.bounds.max.x")
  end)
  ba.setup.status("pattern", function(ctx)
    local patternType = ctx.data.getString("game.pattern.type")
    local hasPatterns = #parseIndex(ctx.data.getString("game.patterns.index")) > 0
    if patternType == nil or patternType == "" then
      if hasPatterns then patternType = "static" else return false end
    end
    local isProcedural = patternType:lower() == "procedural"
    return isProcedural or hasPatterns
  end)
  ba.setup.status("musictime", function(ctx)
    return ctx.data.getDouble("basic.initial_music_time", 0.0) > 0.0
  end)
  ba.setup.status("searchtime", function(ctx)
    return ctx.data.getDouble("basic.search_time", 0.0) > 0.0
  end)
  ba.setup.status("decreasetime", function(ctx)
    return ctx.data.getDouble("basic.decrease_time", 0.0) > 0.0
  end)
  ba.setup.status("mintime", function(ctx)
    return ctx.data.getDouble("basic.min_search_time", 0.0) > 0.0
  end)
end

return M

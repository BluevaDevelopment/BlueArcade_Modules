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

-- "world,x,y,z,MATERIAL" per entry, matching the real setup command's own save format.
local function parseBlockList(raw)
  local blocks = {}
  for _, entry in ipairs(raw) do
    local x, y, z, material = entry:match("^[^,]+,(-?%d+),(-?%d+),(-?%d+),([%u_]+)$")
    if x ~= nil then
      blocks[#blocks + 1] = { x = tonumber(x), y = tonumber(y), z = tonumber(z), material = material }
    end
  end
  return blocks
end

function M.createFallbackPattern(session, floor)
  local materials = session.config.getStringList("fallback_pattern.materials")
  if #materials == 0 then
    materials = { "WHITE_CONCRETE", "LIGHT_BLUE_CONCRETE", "PINK_CONCRETE" }
  end

  local minX, maxX = math.min(floor.min.x, floor.max.x), math.max(floor.min.x, floor.max.x)
  local minY, maxY = math.min(floor.min.y, floor.max.y), math.max(floor.min.y, floor.max.y)
  local minZ, maxZ = math.min(floor.min.z, floor.max.z), math.max(floor.min.z, floor.max.z)

  local blocks = {}
  for x = math.floor(minX), math.floor(maxX) do
    for y = math.floor(minY), math.floor(maxY) do
      for z = math.floor(minZ), math.floor(maxZ) do
        blocks[#blocks + 1] = { x = x, y = y, z = z, material = materials[math.random(#materials)] }
      end
    end
  end
  return { blocks = blocks, targetMaterials = materials }
end

function M.loadPatterns(session, floor)
  local patterns = {}
  local order = {}
  local index = parseIndex(session.dataAccess.getGameDataString("game.patterns.index"))

  for _, name in ipairs(index) do
    local raw = session.dataAccess.getGameDataStringList("game.patterns." .. name)
    local blocks = parseBlockList(raw)
    if #blocks > 0 then
      patterns[name] = { blocks = blocks }
      order[#order + 1] = name
    end
  end

  if next(patterns) == nil and floor ~= nil then
    patterns.fallback = M.createFallbackPattern(session, floor)
    order[1] = "fallback"
    for _, handle in ipairs(session.players()) do
      session.messages.sendRaw(handle, "<yellow>[BlockParty]</yellow> <gray>Fallback pattern generated because none were configured.</gray>")
    end
  end

  return patterns, order
end

function M.selectPatternKey(state, firstRound)
  if firstRound and state.initialPatternKey ~= nil and state.patterns[state.initialPatternKey] ~= nil then
    return state.initialPatternKey
  end
  if #state.order == 0 then return nil end
  return state.order[math.random(#state.order)]
end

local function distinctMaterials(blocks)
  local seen = {}
  local materials = {}
  for _, block in ipairs(blocks) do
    if not seen[block.material] then
      seen[block.material] = true
      materials[#materials + 1] = block.material
    end
  end
  return materials
end

function M.selectTargetMaterial(session, pattern)
  local materials = pattern.targetMaterials or distinctMaterials(pattern.blocks)
  local valid = {}
  for _, material in ipairs(materials) do
    if material ~= nil and material ~= "AIR" and material ~= "BARRIER" then
      valid[#valid + 1] = material
    end
  end
  if #valid == 0 then
    local fallback = session.config.getStringList("fallback_pattern.materials")
    return fallback[1] or "AIR"
  end
  return valid[math.random(#valid)]
end

local function mixSeed(seed, round)
  local h = (seed + round * 92821) % 2147483647
  h = (h * 48271) % 2147483647
  return h
end

function M.createProceduralPattern(session, state)
  local candidates = {}
  for _, template in ipairs(state.proceduralTemplates) do
    local valid = false
    for _, known in ipairs(generator.TEMPLATE_TYPES) do
      if known == template then valid = true break end
    end
    if valid then candidates[#candidates + 1] = template end
  end
  if #candidates == 0 then
    for _, template in ipairs(generator.TEMPLATE_TYPES) do candidates[#candidates + 1] = template end
  end

  local fresh = {}
  for _, candidate in ipairs(candidates) do
    local recent = false
    for _, r in ipairs(state.recentProceduralTemplates) do
      if r == candidate then recent = true break end
    end
    if not recent then fresh[#fresh + 1] = candidate end
  end
  if #fresh > 0 then candidates = fresh end

  local roundSeed = mixSeed(state.matchSeed, state.round)
  math.randomseed(roundSeed)
  local template = candidates[math.random(#candidates)]

  local noRepeat = session.config.getInt("procedural_patterns.no_repeat", 3)
  if noRepeat > 0 then
    state.recentProceduralTemplates[#state.recentProceduralTemplates + 1] = template
    while #state.recentProceduralTemplates > noRepeat do
      table.remove(state.recentProceduralTemplates, 1)
    end
  end

  local floor = state.floor
  local width = math.abs(floor.max.x - floor.min.x) + 1
  local depth = math.abs(floor.max.z - floor.min.z) + 1
  local minSide = math.min(width, depth)
  local area = width * depth

  local minCellsPerSide = math.max(2, session.config.getInt("procedural_patterns.scale.min_cells_per_side", 3))
  local size = math.max(1, math.floor(minSide / math.max(1, minCellsPerSide)))

  local initialColors = math.max(2, session.config.getInt("procedural_patterns.difficulty.initial_colors", 4))
  local maxColors = math.max(initialColors, session.config.getInt("procedural_patterns.difficulty.max_colors", 16))
  local colorIncreaseEvery = math.max(1, session.config.getInt("procedural_patterns.difficulty.color_increase_every", 2))
  local increases = math.floor(math.max(0, state.round - 1) / colorIncreaseEvery)
  local colors = math.min(maxColors, initialColors + increases)

  local minTargetAreaPercent = math.max(1, session.config.getInt("procedural_patterns.min_target_area_percent", 25))
  local minTargetBlocks = math.max(1, math.floor(area * minTargetAreaPercent / 100))

  return generator.generate(floor, template, roundSeed, size, colors, minTargetBlocks)
end

return M

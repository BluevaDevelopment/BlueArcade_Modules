local M = {}

M.TEMPLATE_TYPES = {
  "stripes", "diagonal", "rainbow", "checker", "rings", "sectors",
  "islands", "waves", "spiral", "creeper", "mosaic",
}

local CONCRETE_PALETTE = {
  "WHITE_CONCRETE", "LIGHT_GRAY_CONCRETE", "GRAY_CONCRETE", "BLACK_CONCRETE",
  "BROWN_CONCRETE", "RED_CONCRETE", "ORANGE_CONCRETE", "YELLOW_CONCRETE",
  "LIME_CONCRETE", "GREEN_CONCRETE", "CYAN_CONCRETE", "LIGHT_BLUE_CONCRETE",
  "BLUE_CONCRETE", "PURPLE_CONCRETE", "MAGENTA_CONCRETE", "PINK_CONCRETE",
}

local CREEPER = {
  { 0, 0, 0, 0, 0, 0, 0, 0 },
  { 0, 1, 1, 0, 0, 1, 1, 0 },
  { 0, 1, 1, 0, 0, 1, 1, 0 },
  { 0, 0, 0, 1, 1, 0, 0, 0 },
  { 0, 0, 1, 1, 1, 1, 0, 0 },
  { 0, 0, 1, 1, 1, 1, 0, 0 },
  { 0, 0, 1, 0, 0, 1, 0, 0 },
  { 0, 0, 0, 0, 0, 0, 0, 0 },
}

-- LuaJ has no 64-bit ints/bitwise ops, so legacy's long-based xorshift seed mixing is replaced
-- with a Lehmer/MINSTD multiplicative hash; seed is internal RNG input only, never compared cross-impl.
local function hashIndex(seed, a, b)
  local h = (seed + a * 92821 + b * 68917) % 2147483647
  h = (h * 48271) % 2147483647
  return h
end

local function seedPhase(seed)
  return (hashIndex(seed, 7, 13) % 1000000) / 1000000.0 * math.pi * 2.0
end

local function centerAngle(ctx, x, z)
  local dx = x - (ctx.width - 1) / 2.0
  local dz = z - (ctx.depth - 1) / 2.0
  return math.atan(dz, dx) + math.pi
end

local function distanceFromCenter(ctx, x, z)
  local dx = x - (ctx.width - 1) / 2.0
  local dz = z - (ctx.depth - 1) / 2.0
  return math.sqrt(dx * dx + dz * dz)
end

local function stripesIndex(ctx, x, z)
  return ctx.axisX and math.floor(x / ctx.size) or math.floor(z / ctx.size)
end

local function diagonalIndex(ctx, x, z)
  local coordinate = ctx.useSum and (x + z) or (x - z)
  return math.floor((coordinate + ctx.offset) / ctx.size)
end

local function checkerIndex(ctx, x, z)
  return math.floor((x + ctx.offsetX) / ctx.size) + math.floor((z + ctx.offsetZ) / ctx.size) * 5
end

local function rainbowIndex(ctx, x, z)
  local primary, secondary
  if ctx.rainbowDirection == 0 then
    primary, secondary = x, z
  elseif ctx.rainbowDirection == 1 then
    primary, secondary = z, x
  elseif ctx.rainbowDirection == 2 then
    primary, secondary = x + z, z
  else
    primary, secondary = x - z, x
  end
  local bend = math.sin(secondary / (ctx.size * 2) + ctx.phase) * ctx.size * 2
  return math.floor((primary + ctx.offset + bend) / ctx.size)
end

local function wavesIndex(ctx, x, z)
  local primary = ctx.swapAxes and x or z
  local secondary = ctx.swapAxes and z or x
  local wave = math.sin(secondary / (ctx.size * 2) + ctx.phase) * ctx.size * 2
  return math.floor((primary + ctx.offset + wave) / ctx.size)
end

local function ringsIndex(ctx, x, z)
  local dx = x - (ctx.width - 1) / 2.0 - ctx.shiftX
  local dz = z - (ctx.depth - 1) / 2.0 - ctx.shiftZ
  return math.floor(math.sqrt(dx * dx + dz * dz) / ctx.size)
end

local function sectorIndex(ctx, x, z)
  local angle = centerAngle(ctx, x, z) + ctx.phase
  return math.floor(angle / (math.pi * 2.0) * #ctx.palette)
end

local function spiralIndex(ctx, x, z)
  local angle = centerAngle(ctx, x, z) + ctx.phase
  return math.floor(distanceFromCenter(ctx, x, z) / ctx.size + ctx.spiralDirection * angle / (math.pi * 2.0) * 4.0)
end

local function nearestIsland(ctx, x, z)
  local best = 0
  local bestDistance = math.huge
  for i, point in ipairs(ctx.islands) do
    local dx = x - point.x
    local dz = z - point.z
    local distance = dx * dx + dz * dz
    if distance < bestDistance then
      bestDistance = distance
      best = i - 1
    end
  end
  return best
end

local function creeperMaterial(ctx, x, z)
  local px = math.min(7, math.floor(x * 8 / ctx.width))
  local pz = math.min(7, math.floor(z * 8 / ctx.depth))
  if CREEPER[pz + 1][px + 1] == 1 then
    return "BLACK_CONCRETE"
  end
  for _, material in ipairs(ctx.palette) do
    if material ~= "BLACK_CONCRETE" then return material end
  end
  return "GREEN_CONCRETE"
end

local function mosaicIndex(ctx, x, z)
  local cellX = math.floor(x / ctx.size)
  local cellZ = math.floor(z / ctx.size)
  return hashIndex(ctx.seed, cellX, cellZ)
end

local function materialAt(ctx, x, z)
  if ctx.template == "creeper" then
    return creeperMaterial(ctx, x, z)
  end

  local index
  if ctx.template == "stripes" then index = stripesIndex(ctx, x, z)
  elseif ctx.template == "diagonal" then index = diagonalIndex(ctx, x, z)
  elseif ctx.template == "rainbow" then index = rainbowIndex(ctx, x, z)
  elseif ctx.template == "checker" then index = checkerIndex(ctx, x, z)
  elseif ctx.template == "rings" then index = ringsIndex(ctx, x, z)
  elseif ctx.template == "sectors" then index = sectorIndex(ctx, x, z)
  elseif ctx.template == "islands" then index = nearestIsland(ctx, x, z)
  elseif ctx.template == "waves" then index = wavesIndex(ctx, x, z)
  elseif ctx.template == "spiral" then index = spiralIndex(ctx, x, z)
  elseif ctx.template == "mosaic" then index = mosaicIndex(ctx, x, z)
  else index = 0 end

  local i = index % #ctx.palette
  if i < 0 then i = i + #ctx.palette end
  return ctx.palette[i + 1]
end

local function shuffle(list)
  for i = #list, 2, -1 do
    local j = math.random(i)
    list[i], list[j] = list[j], list[i]
  end
end

local function createIslands(width, depth, size)
  local count = math.max(16, math.min(128, math.floor((width * depth) / math.max(16, size * size * 4))))
  local points = {}
  for i = 1, count do
    points[i] = { x = math.random(0, width - 1), z = math.random(0, depth - 1) }
  end
  return points
end

-- floor: {min={x,y,z}, max={x,y,z}}. Returns { blocks = {{x=,y=,z=,material=}, ...}, targetMaterials = {...} }.
function M.generate(floor, template, seed, size, colorCount, minTargetBlocks)
  math.randomseed(seed)

  local minX = math.min(math.floor(floor.min.x), math.floor(floor.max.x))
  local maxX = math.max(math.floor(floor.min.x), math.floor(floor.max.x))
  local minY = math.min(math.floor(floor.min.y), math.floor(floor.max.y))
  local maxY = math.max(math.floor(floor.min.y), math.floor(floor.max.y))
  local minZ = math.min(math.floor(floor.min.z), math.floor(floor.max.z))
  local maxZ = math.max(math.floor(floor.min.z), math.floor(floor.max.z))
  local width = maxX - minX + 1
  local depth = maxZ - minZ + 1
  size = math.max(1, size)

  local shuffled = {}
  for i, material in ipairs(CONCRETE_PALETTE) do shuffled[i] = material end
  shuffle(shuffled)
  local selectedColors = math.max(2, math.min(colorCount, #shuffled))
  local palette = {}
  for i = 1, selectedColors do palette[i] = shuffled[i] end

  local ctx = {
    template = template, width = width, depth = depth, size = size, seed = seed, palette = palette,
    axisX = math.random() < 0.5,
    useSum = math.random() < 0.5,
    offset = math.random(0, math.max(1, size * #palette) - 1),
    offsetX = math.random(0, math.max(1, size * #palette) - 1),
    offsetZ = math.random(0, math.max(1, size * #palette) - 1),
    rainbowDirection = math.random(0, 3),
    spiralDirection = (math.random() < 0.5) and 1.0 or -1.0,
    swapAxes = math.random() < 0.5,
    phase = seedPhase(seed),
    shiftX = math.random(0, 7) - 3.5,
    shiftZ = math.random(0, 7) - 3.5,
  }
  ctx.islands = template == "islands" and createIslands(width, depth, size) or {}

  local blocks = {}
  local counts = {}
  for x = 0, width - 1 do
    for z = 0, depth - 1 do
      local material = materialAt(ctx, x, z)
      for y = minY, maxY do
        blocks[#blocks + 1] = { x = minX + x, y = y, z = minZ + z, material = material }
        counts[material] = (counts[material] or 0) + 1
      end
    end
  end

  local targets = {}
  for material, count in pairs(counts) do
    if count >= minTargetBlocks then targets[#targets + 1] = material end
  end
  if #targets == 0 then
    for material in pairs(counts) do targets[#targets + 1] = material end
  end

  return { blocks = blocks, targetMaterials = targets }
end

return M

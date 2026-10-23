local M = {}

local DEFAULTS = {
  fireball = { "OBSIDIAN", "CRYING_OBSIDIAN", "END_STONE", "GLASS" },
  tnt = { "OBSIDIAN", "CRYING_OBSIDIAN", "GLASS" },
}

local function normalize(name)
  local normalized = name:match("^%s*(.-)%s*$"):upper()
  return normalized == "ENDER_STONE" and "END_STONE" or normalized
end

function M.protectedBlocks(session, kind)
  local path = "special_items." .. kind .. ".protected_blocks"
  local configured = DEFAULTS[kind]
  if session.config.contains(path) then configured = session.config.getStringList(path) or {} end
  local blocks = {}
  for _, name in ipairs(configured) do
    local key = normalize(name)
    if key ~= "" then blocks[key] = true end
  end
  return blocks
end

function M.protects(blocks, material)
  return blocks[normalize(material)] == true
end

function M.shields(session, blocks, origin, target)
  if next(blocks) == nil then return false end
  local x, y, z = math.floor(origin.x), math.floor(origin.y), math.floor(origin.z)
  local tx, ty, tz = math.floor(target.x), math.floor(target.y), math.floor(target.z)
  local dx, dy, dz = tx + 0.5 - origin.x, ty + 0.5 - origin.y, tz + 0.5 - origin.z
  if dx < 0 and origin.x == x then x = x - 1 end
  if dy < 0 and origin.y == y then y = y - 1 end
  if dz < 0 and origin.z == z then z = z - 1 end
  local function axis(position, cell, delta)
    if delta == 0 then return 0, math.huge, math.huge end
    local step = delta > 0 and 1 or -1
    return step, math.abs(1 / delta), ((step > 0 and cell + 1 or cell) - position) / delta
  end
  local sx, stepX, nextX = axis(origin.x, x, dx)
  local sy, stepY, nextY = axis(origin.y, y, dy)
  local sz, stepZ, nextZ = axis(origin.z, z, dz)
  -- Visit every crossed voxel, excluding the target block itself.
  while x ~= tx or y ~= ty or z ~= tz do
    if M.protects(blocks, session.world.blockTypeAt(x, y, z)) then return true end
    local next = math.min(nextX, nextY, nextZ)
    if nextX <= next + 1e-12 then x = x + sx; nextX = nextX + stepX end
    if nextY <= next + 1e-12 then y = y + sy; nextY = nextY + stepY end
    if nextZ <= next + 1e-12 then z = z + sz; nextZ = nextZ + stepZ end
  end
  return false
end

return M

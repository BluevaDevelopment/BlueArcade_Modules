--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Cage block entries are "world,x,y,z,material" (5-part) or "world,minX,minY,minZ,maxX,maxY,maxZ,
-- material" (8-part) strings from setup.lua's saveRegionBlocks snapshot, parsed like legacy.
local M = {}

local function splitCommas(entry)
  local parts = {}
  for part in entry:gmatch("[^,]+") do
    parts[#parts + 1] = part
  end
  return parts
end

function M.loadCageBlocks(session)
  return session.dataAccess.getGameDataStringList("game.beast_cage.blocks")
end

function M.clearCage(session)
  local blocks = session.state.cageBlocks
  if #blocks == 0 then
    local min = session.dataAccess.getGameLocation("game.beast_cage.bounds.min")
    local max = session.dataAccess.getGameLocation("game.beast_cage.bounds.max")
    if min and max then
      local minX, maxX = math.min(math.floor(min.x), math.floor(max.x)), math.max(math.floor(min.x), math.floor(max.x))
      local minY, maxY = math.min(math.floor(min.y), math.floor(max.y)), math.max(math.floor(min.y), math.floor(max.y))
      local minZ, maxZ = math.min(math.floor(min.z), math.floor(max.z)), math.max(math.floor(min.z), math.floor(max.z))
      for x = minX, maxX do
        for y = minY, maxY do
          for z = minZ, maxZ do
            session.world.setBlockType(x, y, z, "AIR")
          end
        end
      end
    end
    return
  end

  for _, entry in ipairs(blocks) do
    local parts = splitCommas(entry)
    if #parts == 5 or #parts == 8 then
      local startX, startY, startZ = tonumber(parts[2]), tonumber(parts[3]), tonumber(parts[4])
      if startX and startY and startZ then
        local endX = #parts == 8 and tonumber(parts[5]) or startX
        local endY = #parts == 8 and tonumber(parts[6]) or startY
        local endZ = #parts == 8 and tonumber(parts[7]) or startZ
        for x = startX, endX do
          for y = startY, endY do
            for z = startZ, endZ do
              session.world.setBlockType(x, y, z, "AIR")
            end
          end
        end
      end
    end
  end
end

function M.restoreCage(session)
  local blocks = session.state.cageBlocks
  if #blocks == 0 then
    return
  end

  for _, entry in ipairs(blocks) do
    local parts = splitCommas(entry)
    if #parts == 8 then
      local startX, startY, startZ = tonumber(parts[2]), tonumber(parts[3]), tonumber(parts[4])
      local endX, endY, endZ = tonumber(parts[5]), tonumber(parts[6]), tonumber(parts[7])
      local material = parts[8]
      if startX and startY and startZ and endX and endY and endZ and material then
        for x = startX, endX do
          for y = startY, endY do
            for z = startZ, endZ do
              session.world.setBlockType(x, y, z, material)
            end
          end
        end
      end
    end
  end
end

return M

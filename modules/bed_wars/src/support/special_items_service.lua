--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy SpecialItemHandler.java - a dozen small kit-item mechanics triggered off a held
-- item's "special" tag. `getSpecialTag` preserves legacy's two-tier lookup: a PDC tag first
-- (replacing legacy's lore-text `[SPECIAL:xxx]` parsing), then a material-type fallback.
local gameManager = require("game_manager")

local MATERIAL_SPECIAL_FALLBACK = {
  FIRE_CHARGE = "fireball", TNT = "tnt", EGG = "bridge-egg", MILK_BUCKET = "magic-milk",
  SNOWBALL = "bedbug", HORSE_SPAWN_EGG = "dream-defender", SPONGE = "sponge", CHEST = "tower",
}
local TEAM_WOOL = {
  red = "RED_WOOL", blue = "BLUE_WOOL", green = "GREEN_WOOL", yellow = "YELLOW_WOOL",
  aqua = "CYAN_WOOL", cyan = "CYAN_WOOL", white = "WHITE_WOOL", black = "BLACK_WOOL",
  gray = "GRAY_WOOL", grey = "GRAY_WOOL", dark_gray = "GRAY_WOOL", dark_grey = "GRAY_WOOL",
  light_purple = "MAGENTA_WOOL", magenta = "MAGENTA_WOOL", pink = "PINK_WOOL",
  orange = "ORANGE_WOOL", gold = "ORANGE_WOOL", lime = "LIME_WOOL", brown = "BROWN_WOOL",
  light_blue = "LIGHT_BLUE_WOOL", purple = "PURPLE_WOOL",
}

local M = {}

local function getSpecialTag(session, handle)
  local tag = session.player.mainHandItemTag(handle, "bedwars_special")
  if tag then return tag:lower() end
  local material = session.player.itemInMainHandType(handle)
  local fallback = material and MATERIAL_SPECIAL_FALLBACK[material]
  return fallback
end

local function getTeamWool(session, handle)
  if not session.teams.isEnabled() then return "WHITE_WOOL" end
  local team = session.teams.forPlayer(handle)
  if not team then return "WHITE_WOOL" end
  return TEAM_WOOL[team.id:lower()] or "WHITE_WOOL"
end

local function resolveTeamId(session, handle)
  if not session.teams.isEnabled() then return "solo" end
  local team = session.teams.forPlayer(handle)
  return (team and team.id) or "solo"
end

local function consumeOneItem(session, handle)
  session.player.consumeMainHandItem(handle)
end

local function isRightClick(action)
  return action == "RIGHT_CLICK_AIR" or action == "RIGHT_CLICK_BLOCK"
end

local function handleFireball(session, handle, e)
  if not isRightClick(e.action) then return end

  local now = os.clock()
  local last = session.state.fireballCooldowns[handle] or 0
  local cooldownSeconds = session.config.getInt("special_items.fireball.cooldown_seconds", 1)
  if cooldownSeconds > 0 and (now - last) < cooldownSeconds then
    return
  end
  session.state.fireballCooldowns[handle] = now

  e:cancel()
  local speed = session.config.getDouble("special_items.fireball.speed", 1.5)
  local yield = session.config.getDouble("special_items.fireball.explosion_size", 3.0)
  local projectile = session.player.launchSpecialProjectile(handle, "FIREBALL", speed, yield, false)
  if projectile then
    session.state.trackedFireballs[projectile] = true
  end

  consumeOneItem(session, handle)
  local launchSound = session.config.getString("special_items.fireball.launch_sound") or "ENTITY_GHAST_SHOOT"
  local volume = session.config.getDouble("special_items.fireball.launch_volume", 1.0)
  local pitch = session.config.getDouble("special_items.fireball.launch_pitch", 1.0)
  session.sounds.playDirect(handle, launchSound, volume, pitch)
end

local function handleTNT(session, handle, e)
  if e.action ~= "RIGHT_CLICK_BLOCK" or not e.clickedBlockLocation then return end
  e:cancel()

  -- Approximates "block adjacent to the clicked face" as "block above" - the click face isn't
  -- exposed on `player_interact`'s event table, and floor right-clicks are the common case.
  local loc = e.clickedBlockLocation
  local spawnLoc = { x = math.floor(loc.x) + 0.5, y = math.floor(loc.y) + 1, z = math.floor(loc.z) + 0.5 }
  local tnt = session.world.spawnEntity(spawnLoc, "TNT")
  if tnt then
    session.entities.setFuseTicks(tnt, session.config.getInt("special_items.tnt.fuse_ticks", 40))
  end
  consumeOneItem(session, handle)
end

local function handleBridgeEgg(session, handle, e)
  if not isRightClick(e.action) then return end
  e:cancel()
  local speed = session.config.getDouble("special_items.bridge_egg.projectile_speed", 1.5)
  local projectile = session.player.launchSpecialProjectile(handle, "EGG", speed, nil, false, "bridge-egg")
  if projectile then
    session.state.specialProjectiles[projectile] = "bridge-egg"
  end
  consumeOneItem(session, handle)
end

local function handleMagicMilk(session, handle, e)
  if not isRightClick(e.action) then return end
  e:cancel()
  consumeOneItem(session, handle)
  local seconds = session.config.getInt("special_items.magic_milk.trap_immunity_seconds", 30)
  local message = session.config.translation(handle, "messages.special_items.magic_milk_used")
  if message then
    session.messages.sendRaw(handle, message:gsub("{seconds}", tostring(seconds)))
  end
end

local function handleBedbug(session, handle, e)
  if not isRightClick(e.action) then return end
  e:cancel()
  local speed = session.config.getDouble("special_items.bedbug.projectile_speed", 1.5)
  local projectile = session.player.launchSpecialProjectile(handle, "SNOWBALL", speed, nil, false, "bedbug")
  if projectile then
    session.state.specialProjectiles[projectile] = "bedbug"
  end
  consumeOneItem(session, handle)
end

local function handleDreamDefender(session, handle, e)
  if e.action ~= "RIGHT_CLICK_BLOCK" or not e.clickedBlockLocation then return end
  e:cancel()
  local loc = e.clickedBlockLocation
  local spawnLoc = { x = math.floor(loc.x) + 0.5, y = math.floor(loc.y) + 1, z = math.floor(loc.z) + 0.5 }
  local golem = session.world.spawnEntity(spawnLoc, "IRON_GOLEM")
  if golem then
    local name = session.config.getString("special_items.dream_defender.name") or "Dream Defender"
    local nameVisible = session.config.getBoolean("special_items.dream_defender.name_visible", true)
    session.entities.setCustomName(golem, name, nameVisible)
  end
  consumeOneItem(session, handle)
end

local function handleSponge(session, handle, e)
  if e.action ~= "RIGHT_CLICK_BLOCK" or not e.clickedBlockLocation then return end
  e:cancel()
  local center = e.clickedBlockLocation
  local radius = math.max(0, session.config.getInt("special_items.sponge.radius_blocks", 2))
  for x = -radius, radius do
    for y = -radius, radius do
      for z = -radius, radius do
        local bx, by, bz = math.floor(center.x) + x, math.floor(center.y) + y, math.floor(center.z) + z
        if session.world.blockTypeAt(bx, by, bz) == "WATER" then
          session.world.setBlockType(bx, by, bz, "AIR")
        end
      end
    end
  end
  consumeOneItem(session, handle)
end

local function handleTower(session, handle, e)
  if e.action ~= "RIGHT_CLICK_BLOCK" or not e.clickedBlockLocation then return end
  e:cancel()
  local base = e.clickedBlockLocation
  local wool = getTeamWool(session, handle)
  local height = math.max(1, session.config.getInt("special_items.tower.height_blocks", 5))
  local bx, bz = math.floor(base.x), math.floor(base.z)
  for i = 0, height - 1 do
    local by = math.floor(base.y) + i
    if session.world.blockTypeAt(bx, by, bz) == "AIR" then
      session.world.setBlockType(bx, by, bz, wool)
      gameManager.trackPlacedBlock(session, bx, by, bz)
    end
  end
  consumeOneItem(session, handle)
end

local function applySpecialPlaceholders(session, handle, input, special)
  return input
    :gsub("{player}", session.player.name(handle))
    :gsub("{uuid}", handle)
    :gsub("{arena}", tostring(session.arenaId))
    :gsub("{arena_id}", tostring(session.arenaId))
    :gsub("{team}", resolveTeamId(session, handle))
    :gsub("{special}", special)
end

local function runConfiguredSpecialAction(session, handle, special, rawAction)
  if not rawAction or rawAction == "" then return end
  local action = applySpecialPlaceholders(session, handle, rawAction, special)
  local type, data = action:match("^([^:]+):?(.*)$")
  type = type and type:lower() or ""
  if type == "message" then
    session.messages.sendRaw(handle, data)
  elseif type == "broadcast" then
    for _, p in ipairs(session.players()) do
      session.messages.sendRaw(p, data)
    end
  elseif type == "console" or type == "console-command" then
    session.player.runConsoleCommand(data)
  elseif type == "player" or type == "player-command" then
    session.player.runCommand(handle, data)
  elseif type == "sound" then
    local parts = {}
    for p in data:gmatch("[^:]+") do parts[#parts + 1] = p end
    if parts[1] then
      session.sounds.playDirect(handle, parts[1], tonumber(parts[2]) or 1.0, tonumber(parts[3]) or 1.0)
    end
  elseif type == "effect" or type == "potion-effect" then
    local parts = {}
    for p in data:gmatch("[^:]+") do parts[#parts + 1] = p end
    if #parts >= 3 then
      local ambient = parts[4] == "true"
      local particles = parts[5] == nil or parts[5] == "true"
      session.player.addPotionEffect(handle, parts[1], tonumber(parts[2]), tonumber(parts[3]), ambient, particles)
    end
  elseif type == "give" then
    local parts = {}
    for p in data:gmatch("[^:]+") do parts[#parts + 1] = p end
    if parts[1] then
      session.player.giveItem(handle, parts[1], math.max(1, tonumber(parts[2]) or 1), -1)
    end
  end
end

local function handleConfiguredSpecial(session, handle, e, special)
  if not isRightClick(e.action) then return end
  local basePath = "shop.specials." .. special
  local actions = session.config.getStringListFrom("shop.yml", basePath .. ".actions")
  if #actions == 0 then return end

  e:cancel()
  for _, rawAction in ipairs(actions) do
    runConfiguredSpecialAction(session, handle, special, rawAction)
  end
  if session.config.getBooleanFrom("shop.yml", basePath .. ".consume", true) then
    consumeOneItem(session, handle)
  end
end

local SPECIAL_HANDLERS = {
  fireball = handleFireball,
  tnt = handleTNT,
  ["bridge-egg"] = handleBridgeEgg,
  ["magic-milk"] = handleMagicMilk,
  bedbug = handleBedbug,
  ["dream-defender"] = handleDreamDefender,
  sponge = handleSponge,
  tower = handleTower,
}

local function handleFireballHit(session, handle, e)
  local loc = e.hitBlock or session.player.location(handle)
  local explosionSize = session.config.getDouble("special_items.fireball.explosion_size", 3.0)
  local horizontalKb = session.config.getDouble("special_items.fireball.knockback_horizontal", 1.0)
  local verticalKb = session.config.getDouble("special_items.fireball.knockback_vertical", 0.65)
  local damageSelf = session.config.getDouble("special_items.fireball.damage_self", 2.0)
  local damageEnemy = session.config.getDouble("special_items.fireball.damage_enemy", 2.0)
  local damageTeammates = session.config.getDouble("special_items.fireball.damage_teammates", 0.0)

  session.world.createExplosion(loc, explosionSize, false, false)

  local radius = math.ceil(explosionSize)
  local bx, by, bz = math.floor(loc.x), math.floor(loc.y), math.floor(loc.z)
  for dx = -radius, radius do
    for dy = -radius, radius do
      for dz = -radius, radius do
        if dx * dx + dy * dy + dz * dz <= radius * radius then
          local x, y, z = bx + dx, by + dy, bz + dz
          local key = x .. ":" .. y .. ":" .. z
          if session.world.blockTypeAt(x, y, z) ~= "AIR" and session.state.playerPlacedBlocks[key] then
            session.world.setBlockType(x, y, z, "AIR")
            session.state.playerPlacedBlocks[key] = nil
          end
        end
      end
    end
  end

  for _, target in ipairs(session.players()) do
    if session.isPlaying(target) then
      local targetLoc = session.player.location(target)
      local dx, dy, dz = targetLoc.x - loc.x, targetLoc.y - loc.y, targetLoc.z - loc.z
      if math.abs(dx) <= explosionSize and math.abs(dy) <= explosionSize and math.abs(dz) <= explosionSize then
        local horizLen = math.sqrt(dx * dx + dz * dz)
        local hx = horizLen > 0 and -(dx / horizLen) * horizontalKb or 0
        local hz = horizLen > 0 and -(dz / horizLen) * horizontalKb or 0
        local vy = dy
        if vy < 0 then vy = vy + 1.5 end
        if vy <= 0.5 then
          vy = verticalKb * 1.5
        else
          vy = vy * verticalKb * 1.5
        end
        session.player.setVelocity(target, hx, vy, hz)

        if target == handle then
          if damageSelf > 0 then session.player.damage(target, damageSelf) end
        else
          local sameTeam = false
          if session.teams.isEnabled() then
            local t1, t2 = session.teams.forPlayer(handle), session.teams.forPlayer(target)
            sameTeam = t1 and t2 and t1.id:lower() == t2.id:lower()
          end
          if sameTeam then
            if damageTeammates > 0 then session.player.damage(target, damageTeammates) end
          else
            if damageEnemy > 0 then session.player.damage(target, damageEnemy) end
          end
        end
      end
    end
  end
end

local function buildBridge(session, hitLocation, material)
  local length = math.max(1, session.config.getInt("special_items.bridge_egg.length_blocks", 10))
  local halfWidth = math.max(0, session.config.getInt("special_items.bridge_egg.half_width_blocks", 1))
  local bx, by, bz = math.floor(hitLocation.x), math.floor(hitLocation.y), math.floor(hitLocation.z)
  for i = 0, length - 1 do
    for j = -halfWidth, halfWidth do
      if session.world.blockTypeAt(bx + i, by + j, bz) == "AIR" then
        session.world.setBlockType(bx + i, by + j, bz, material)
      end
    end
  end
end

function M.register()
  ba.events.on("player_interact", function(session, e)
    if not session.isPlaying(e.player) then return end
    local special = getSpecialTag(session, e.player)
    if not special then return end

    local handler = SPECIAL_HANDLERS[special]
    if handler then
      handler(session, e.player, e)
    else
      handleConfiguredSpecial(session, e.player, e, special)
    end
  end)

  ba.events.on("projectile_hit", function(session, e)
    if not session.isPlaying(e.shooter) then return end

    if session.state.trackedFireballs[e.projectile] then
      session.state.trackedFireballs[e.projectile] = nil
      handleFireballHit(session, e.shooter, e)
      return
    end

    local special = session.state.specialProjectiles[e.projectile]
    if special == "bridge-egg" then
      session.state.specialProjectiles[e.projectile] = nil
      local loc = e.hitBlock or session.player.location(e.shooter)
      local useTeamWool = session.config.getBoolean("special_items.bridge_egg.use_team_wool", true)
      local material = useTeamWool and getTeamWool(session, e.shooter)
        or (session.config.getString("special_items.bridge_egg.fallback_material") or "WHITE_WOOL")
      buildBridge(session, loc, material)
    elseif special == "bedbug" then
      session.state.specialProjectiles[e.projectile] = nil
      local loc = e.hitBlock or session.player.location(e.shooter)
      session.world.spawnEntity(loc, "SILVERFISH")
    end
  end)
end

return M

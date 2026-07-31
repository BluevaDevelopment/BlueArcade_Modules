-- Mirrors legacy ParticleService.java. Menu built directly in Lua (see options_service.lua's own
-- doc comment for why - ParticleMenuHolder.java isn't ported). The actual per-second particle tick
-- (BuildBattleGame.startParticleTask) lives in game_manager.lua, not here - this file only manages
-- the menu and the plot-owned particle list itself.
local BACK_SLOT = 45
local REMOVE_SLOT = 49

-- effect, icon, name - matches ParticleService.PARTICLES exactly.
local PARTICLES = {
  { effect = "FLAME", icon = "BLAZE_POWDER", name = "<gold>Flame" },
  { effect = "HEART", icon = "RED_DYE", name = "<red>Heart" },
  { effect = "NOTE", icon = "NOTE_BLOCK", name = "<yellow>Note" },
  { effect = "CRIT", icon = "IRON_SWORD", name = "<gray>Crit" },
  { effect = "WITCH", icon = "POTION", name = "<dark_purple>Witch Magic" },
  { effect = "DRIP_WATER", icon = "WATER_BUCKET", name = "<aqua>Water Drip" },
  { effect = "DRIP_LAVA", icon = "LAVA_BUCKET", name = "<gold>Lava Drip" },
  { effect = "ANGRY_VILLAGER", icon = "EMERALD", name = "<red>Angry Villager" },
  { effect = "HAPPY_VILLAGER", icon = "WHEAT", name = "<green>Happy Villager" },
  { effect = "PORTAL", icon = "OBSIDIAN", name = "<dark_purple>Portal" },
  { effect = "ENCHANT", icon = "ENCHANTING_TABLE", name = "<light_purple>Enchant" },
  { effect = "FIREWORKS_SPARK", icon = "FIREWORK_ROCKET", name = "<aqua>Firework" },
  { effect = "LAVA", icon = "MAGMA_BLOCK", name = "<gold>Lava" },
  { effect = "SLIME", icon = "SLIME_BALL", name = "<green>Slime" },
  { effect = "SNOWBALL", icon = "SNOWBALL", name = "<white>Snowball" },
  { effect = "CLOUD", icon = "WHITE_WOOL", name = "<white>Cloud" },
  { effect = "SMOKE_NORMAL", icon = "COAL", name = "<gray>Smoke" },
  { effect = "SMOKE_LARGE", icon = "CHARCOAL", name = "<dark_gray>Large Smoke" },
  { effect = "SPELL", icon = "GLOWSTONE_DUST", name = "<yellow>Spell" },
  { effect = "SPELL_INSTANT", icon = "SUGAR", name = "<white>Instant Spell" },
  { effect = "SPELL_MOB", icon = "NETHER_WART", name = "<dark_purple>Mob Spell" },
  { effect = "TOWN_AURA", icon = "GRASS_BLOCK", name = "<green>Town Aura" },
  { effect = "BUBBLE", icon = "BUBBLE_CORAL", name = "<aqua>Bubble" },
  { effect = "SPLASH", icon = "PRISMARINE_SHARD", name = "<blue>Splash" },
  { effect = "SNOW_SHOVEL", icon = "WOODEN_SHOVEL", name = "<white>Snow Shovel" },
  { effect = "EXPLOSION", icon = "TNT", name = "<red>Explosion" },
  { effect = "EXPLOSION_LARGE", icon = "TNT", name = "<dark_red>Large Explosion" },
  { effect = "SOUL_FIRE_FLAME", icon = "SOUL_TORCH", name = "<aqua>Soul Flame" },
  { effect = "ASH", icon = "GRAY_DYE", name = "<gray>Ash" },
  { effect = "SOUL", icon = "SOUL_LANTERN", name = "<aqua>Soul" },
  { effect = "FALLING_SPORE_BLOSSOM", icon = "SPORE_BLOSSOM", name = "<green>Spore Blossom" },
  { effect = "SNOWFLAKE", icon = "SNOW_BLOCK", name = "<white>Snowflake" },
  { effect = "GLOW", icon = "GLOWSTONE", name = "<yellow>Glow" },
  { effect = "GLOW_SQUID_INK", icon = "GLOW_INK_SAC", name = "<aqua>Glow Ink" },
  { effect = "TOTEM_OF_UNDYING", icon = "TOTEM_OF_UNDYING", name = "<gold>Totem" },
  { effect = "WAX_ON", icon = "HONEYCOMB", name = "<gold>Wax On" },
  { effect = "WAX_OFF", icon = "HONEYCOMB", name = "<yellow>Wax Off" },
}

local M = {}

local function sendMessage(session, handle, path)
  local message = session.config.translation(handle, path)
  if message then
    session.messages.sendRaw(handle, message)
  end
end

function M.openParticleMenu(session, handle)
  local items = {}
  local slot = 0
  for _, entry in ipairs(PARTICLES) do
    if slot == BACK_SLOT or slot == REMOVE_SLOT then
      slot = slot + 1
    end
    if slot >= 54 then
      break
    end
    items[#items + 1] = {
      slot = slot, material = entry.icon, amount = 1, name = entry.name, lore = {},
      actions = { "MODULE;build_battle;options particle place " .. entry.effect },
    }
    slot = slot + 1
  end

  items[#items + 1] = {
    slot = BACK_SLOT, material = "ARROW", amount = 1,
    name = session.config.translation(handle, "options.banner.back") or "Back", lore = {},
    actions = { "MODULE;build_battle;options menu main" },
  }
  items[#items + 1] = {
    slot = REMOVE_SLOT, material = "BARRIER", amount = 1,
    name = "<red>Remove Particles", lore = {},
    actions = { "MODULE;build_battle;options particle remove_menu" },
  }

  local title = session.config.translation(handle, "options.particle.title") or "Particles"
  session.menu.open(handle, title, 54, items, {})
end

function M.openRemoveMenu(session, handle)
  local plot = session.state.playerPlot[handle]
  if not plot then
    return
  end
  local particles = session.state.plotParticles[handle] or {}
  local items = {}
  for i, particle in ipairs(particles) do
    if i - 1 >= 53 then
      break
    end
    items[#items + 1] = {
      slot = i - 1, material = "BLAZE_POWDER", amount = 1,
      name = "<yellow>" .. particle.effect, lore = { "<red>Click to remove" },
      actions = { "MODULE;build_battle;options particle remove " .. (i - 1) },
    }
  end
  items[#items + 1] = {
    slot = 53, material = "ARROW", amount = 1,
    name = session.config.translation(handle, "options.banner.back") or "Back", lore = {},
    actions = { "MODULE;build_battle;options particle menu" },
  }
  local title = (session.config.translation(handle, "options.particle.title") or "Particles") .. " - Remove"
  session.menu.open(handle, title, 54, items, {})
end

local function placeParticle(session, handle, effect)
  local plot = session.state.playerPlot[handle]
  if not plot then
    return
  end
  local limit = session.config.getInt("particles.limit", 25)
  local particles = session.state.plotParticles[handle] or {}
  if #particles >= limit then
    sendMessage(session, handle, "options.messages.particle_limit_reached")
    return
  end
  particles[#particles + 1] = { location = session.player.location(handle), effect = effect:upper() }
  session.state.plotParticles[handle] = particles
  sendMessage(session, handle, "options.messages.particle_added")
end

local function removeParticle(session, handle, index)
  local particles = session.state.plotParticles[handle]
  if not particles or not particles[index + 1] then
    return
  end
  table.remove(particles, index + 1)
  sendMessage(session, handle, "options.messages.particle_removed")
end

-- args[1] is always "particle" (dispatched by options_service.handleModuleAction).
function M.handleModuleAction(session, handle, args)
  local action = args[2] and args[2]:lower()
  if action == "menu" then
    M.openParticleMenu(session, handle)
    return true
  elseif action == "remove_menu" then
    M.openRemoveMenu(session, handle)
    return true
  elseif action == "place" and args[3] then
    placeParticle(session, handle, args[3])
    return true
  elseif action == "remove" and args[3] then
    removeParticle(session, handle, tonumber(args[3]))
    return true
  end
  return false
end

return M

--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Store zappers supplement the configured loadout; only tagged tools can fire.
local storeService = require("support.store_service")
local M = {}
local tiers = {
  wood = { material = "WOODEN_HOE", shots = 1 },
  stone = { material = "STONE_HOE", shots = 2 },
  iron = { material = "IRON_HOE", shots = 3 },
  diamond = { material = "DIAMOND_HOE", shots = 4 },
}

function M.give(session, beast)
  if not session.config.getBooleanFrom("store.yml", "gameplay.enabled", true) then return end
  local selected = storeService.resolveSelected(session, beast, "zappers")
  if not selected then return end
  local tier = tiers[selected:lower()] or tiers.wood
  local base = "category_settings.zappers.items." .. selected
  session.player.giveEnchantedItem(beast,
    session.config.getStringFrom("store.yml", base .. ".gameplay.material", tier.material),
    1, -1, nil, nil, true,
    session.config.getStringFrom("store.yml", base .. ".name", selected),
    session.config.getStringListFrom("store.yml", base .. ".description"),
    { rftb_zapper = selected })
  session.state.zapperShots = math.max(1, session.config.getIntFrom("store.yml", base .. ".gameplay.shots", tier.shots))
end

local function canUse(session, beast)
  return not session.state.ended and session.phase() == "PLAYING"
    and session.state.beastReleased and session.state.beastId == beast and session.isPlaying(beast)
    and session.config.getBooleanFrom("store.yml", "gameplay.enabled", true)
    and session.config.getBooleanFrom("store.yml", "category_settings.root.enabled", true)
    and session.config.getBooleanFrom("store.yml", "category_settings.zappers.enabled", true)
end

function M.fire(session, beast)
  if not session.player.mainHandItemTag(beast, "rftb_zapper") then return false end
  if not canUse(session, beast) or session.state.zapperShots <= 0 then return true end
  -- Bukkit's snowball launch speed is 1.5; the reference doubles it.
  local shot = session.player.launchSpecialProjectile(beast, "SNOWBALL", 3.0)
  if not shot then return true end
  session.state.zapperProjectiles[shot] = true
  session.state.zapperShots = session.state.zapperShots - 1
  if session.state.zapperShots == 0 then session.player.consumeMainHandItem(beast) end
  return true
end

function M.hit(session, e)
  if not session.state.zapperProjectiles[e.projectile] then return end
  session.state.zapperProjectiles[e.projectile] = nil
  local center = session.entities.location(e.projectile)
  session.entities.remove(e.projectile)
  if not center or not canUse(session, e.shooter) then return end
  local radius = math.max(0, session.config.getDoubleFrom("store.yml", "gameplay.zapper.radius", 2.0))
  local damage = math.max(0, session.config.getDoubleFrom("store.yml", "gameplay.zapper.damage", 5.0))
  local ticks = math.max(1, session.config.getIntFrom("store.yml", "gameplay.zapper.effect_duration_ticks", 200))
  for _, runner in ipairs(session.alivePlayers()) do
    if session.state.ended then break end
    local loc = session.player.location(runner)
    if runner ~= e.shooter and session.isPlaying(runner) and loc
        and math.abs(loc.x - center.x) <= radius and math.abs(loc.y - center.y) <= radius
        and math.abs(loc.z - center.z) <= radius then
      session.player.addPotionEffect(runner, "BLINDNESS", ticks, 4)
      session.player.addPotionEffect(runner, "CONFUSION", ticks, 5)
      session.player.addPotionEffect(runner, "SLOW", ticks, 2)
      session.player.addPotionEffect(runner, "SLOW_DIGGING", ticks, 5)
      session.player.damageBy(runner, damage, e.shooter)
    end
  end
end

function M.cleanup(session)
  for shot in pairs(session.state.zapperProjectiles) do session.entities.remove(shot) end
  session.state.zapperProjectiles = {}
  session.state.zapperShots = 0
end
return M

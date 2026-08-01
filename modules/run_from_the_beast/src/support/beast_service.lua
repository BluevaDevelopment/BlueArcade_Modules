--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

local storeService = require("support.store_service")

local M = {}

local function buildBeastWeights(session, candidates)
  local defaultWeight = session.config.getIntFrom("store.yml", "weights.beast_pass.default", 1)
  local bonusWeight = session.config.getIntFrom("store.yml", "weights.beast_pass.bonus", 3)
  local weights = {}
  for _, handle in ipairs(candidates) do
    weights[handle] = storeService.hasBeastPass(session, handle) and (defaultWeight + bonusWeight) or defaultWeight
  end
  return weights
end

-- Weighted pick via the real StoreAPI beast-pass bonus; degrades to uniform weights when unconfigured, matching legacy's own storeAPI==null fallback.
function M.selectBeast(session)
  local candidates = session.players()
  if #candidates == 0 then
    return
  end

  local weights = buildBeastWeights(session, candidates)
  local totalWeight = 0
  for _, handle in ipairs(candidates) do
    totalWeight = totalWeight + weights[handle]
  end

  local roll = math.random(math.max(totalWeight, 1))
  local cumulative = 0
  local chosen = candidates[1]
  for _, handle in ipairs(candidates) do
    cumulative = cumulative + weights[handle]
    if roll <= cumulative then
      chosen = handle
      break
    end
  end
  session.state.beastId = chosen

  local beastSpawn = session.dataAccess.getGameLocation("game.beast.spawn")
  if beastSpawn then
    session.scheduler.runLater("teleport_beast_" .. session.arenaId, function()
      session.player.teleport(chosen, beastSpawn)
    end, 0)
  end
end

function M.getBeast(session)
  return session.state.beastId
end

-- The vanilla scoreboard-team red tint legacy also applies isn't ported - no raw scoreboard-team
-- binding exists; the beast still glows white via the real GLOWING effect, just not red-tinted.
function M.applyBeastGlow(session, beast)
  if not beast then
    return
  end
  local durationSeconds = math.max(session.state.timeLeftSeconds, 0) + 30
  session.player.addPotionEffect(beast, "GLOWING", durationSeconds * 20, 0)
end

function M.removeBeastGlow(session)
  local beast = M.getBeast(session)
  if beast then
    session.player.removePotionEffect(beast, "GLOWING")
  end
end

return M

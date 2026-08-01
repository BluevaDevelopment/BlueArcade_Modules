-- Mirrors legacy RunFromTheBeastBeastService.java. The beast-pass weighted-selection bonus is
-- store-driven (storeAPI.isUnlocked) - storeAPI is entirely unbound in this project's Lua layer,
-- so every candidate always gets the plain default weight, matching legacy's own
-- `storeAPI != null && ...` guard's false branch exactly (a real pre-existing legacy fallback, not
-- a fabricated simplification). Beast glow uses only the real GLOWING potion effect - the
-- vanilla scoreboard-team red tint legacy also applies is a documented, deliberate gap (the beast
-- still visibly glows white, just not red-tinted; no binding exists for raw scoreboard teams and
-- nothing else has needed one).
local M = {}

function M.selectBeast(session)
  local candidates = session.players()
  if #candidates == 0 then
    return
  end

  local roll = math.random(#candidates)
  local chosen = candidates[roll]
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

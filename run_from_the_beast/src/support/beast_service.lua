local M = {}

-- Store-driven beast-pass weighting always falls back to equal weights (StoreAPI unbound), so a
-- plain uniform pick matches legacy's own `storeAPI != null && ...` guard's false branch exactly.
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

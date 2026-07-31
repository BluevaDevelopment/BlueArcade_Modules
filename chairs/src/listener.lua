local M = {}

function M.register()
  ba.events.on("block_place", function(session, e)
    if session.isPlaying(e.player) then e:cancel() end
  end)

  ba.events.on("player_damage", function(session, e)
    if session.isPlaying(e.player) then e:cancel() end
  end)

  ba.events.on("player_damage_by_entity", function(session, e)
    if e.damager ~= nil and session.isPlaying(e.damager) then e:cancel() end
  end)
end

return M

--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy GuessTheBuildListener.java. isInFloorChangeMode not ported (legacy never calls
-- addFloorChangeMode, always false); player_interact not subscribed (legacy handler body is empty).
local M = {}

local function insidePlot(session, location)
  local plot = session.state.currentBuildPlot
  if plot then
    local x, y, z = location.x, location.y, location.z
    return x >= math.min(plot.min.x, plot.max.x) and x <= math.max(plot.min.x, plot.max.x)
      and y >= math.min(plot.min.y, plot.max.y) and y <= math.max(plot.min.y, plot.max.y)
      and z >= math.min(plot.min.z, plot.max.z) and z <= math.max(plot.min.z, plot.max.z)
  end
  return session.isInsideBounds(location)
end

function M.register()
  ba.events.on("player_move", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end
    if session.phase() ~= "PLAYING" then
      return
    end
    if not session.isInsideBounds(e.to) then
      local spawn = session.state.playerPlotSpawn[e.player]
      if spawn then
        session.player.teleport(e.player, spawn)
      else
        session.respawnPlayer(e.player)
      end
    end
  end)

  ba.events.on("block_break", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end

    if session.state.phase ~= "BUILDING" then
      e:cancel()
      return
    end
    if e.player ~= session.state.currentBuilder then
      e:cancel()
      return
    end
    if not insidePlot(session, e.location) then
      e:cancel()
    end
  end)

  ba.events.on("block_place", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end

    if session.state.phase ~= "BUILDING" then
      e:cancel()
      return
    end
    if e.player ~= session.state.currentBuilder then
      e:cancel()
      return
    end
    if not insidePlot(session, e.location) then
      e:cancel()
    end
  end)

  ba.events.on("player_damage", function(session, e)
    if session.isPlaying(e.player) then
      e:cancel()
    end
  end)

  ba.events.on("player_drop_item", function(session, e)
    if session.isPlaying(e.player) then
      e:cancel()
    end
  end)
end

return M

-- Mirrors legacy BuildBattleListener.java. The BannerMenuHolder/ParticleMenuHolder/HeadMenuHolder click
-- branches aren't ported - those menus are now real session.menu.open menus Core already routes generically.
-- The "cancel inventory clicks outside PLOT_VOTING" guard is a real gap - no inventory_click Lua event exists yet.
local plotVotingService = require("support.plot_voting_service")
local optionsService = require("support.options_service")
local voteService = require("support.vote_service")
local plotService = require("support.plot_service")

local M = {}

local function isInsidePlot(plot, location)
  if not plot or not plot.min or not plot.max then
    return false
  end
  local minX, maxX = math.min(plot.min.x, plot.max.x), math.max(plot.min.x, plot.max.x)
  local minY, maxY = math.min(plot.min.y, plot.max.y), math.max(plot.min.y, plot.max.y)
  local minZ, maxZ = math.min(plot.min.z, plot.max.z), math.max(plot.min.z, plot.max.z)
  return location.x >= minX and location.x <= maxX
    and location.y >= minY and location.y <= maxY
    and location.z >= minZ and location.z <= maxZ
end

function M.register()
  ba.events.on("player_move", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end
    if session.phase() ~= "PLAYING" then
      return
    end

    if session.state.phase == "BUILDING" then
      local plot = session.state.playerPlot[e.player]
      if plot then
        if not isInsidePlot(plot, e.to) then
          e.setTo(plotService.centerLocation(plot.spawn))
        end
        return
      end
    end

    if not session.isInsideBounds(e.to) then
      local spawn = session.state.playerPlotSpawn[e.player]
      if spawn then
        e.setTo(spawn)
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
    local plot = session.state.playerPlot[e.player]
    if plot then
      if not isInsidePlot(plot, e.location) then
        e:cancel()
      end
    elseif not session.isInsideBounds(e.location) then
      e:cancel()
    end
  end)

  ba.events.on("block_place", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end

    if session.state.phase == "PLOT_VOTING" then
      if e.blockType ~= "AIR" then
        plotVotingService.handleVoteItemClick(session, e.player, e.blockType)
      end
      e:cancel()
      return
    end

    if session.state.phase ~= "BUILDING" then
      e:cancel()
      return
    end

    if session.state.floorChangeMode[e.player] then
      e:cancel()
      optionsService.handleFloorChange(session, e.player, e.blockType)
      return
    end

    local plot = session.state.playerPlot[e.player]
    if plot then
      if not isInsidePlot(plot, e.location) then
        e:cancel()
      end
    elseif not session.isInsideBounds(e.location) then
      e:cancel()
    end
  end)

  ba.events.on("player_damage", function(session, e)
    if session.isPlaying(e.player) then
      e:cancel()
    end
  end)

  ba.events.on("player_damage_by_entity", function(session, e)
    if session.isPlaying(e.target) then
      e:cancel()
    end
  end)

  ba.events.on("player_drop_item", function(session, e)
    if session.isPlaying(e.player) then
      e:cancel()
    end
  end)

  ba.events.on("player_interact", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end

    if session.state.phase == "BUILDING" then
      if session.player.itemInMainHandType(e.player) == "NETHER_STAR" then
        optionsService.handleOptionsClick(session, e.player)
        e:cancel()
      end
      return
    end

    if session.state.phase == "PLOT_VOTING" then
      local itemType = session.player.itemInMainHandType(e.player)
      if not itemType then
        return
      end
      plotVotingService.handleVoteItemClick(session, e.player, itemType)
      e:cancel()
    end
  end)

  ba.events.on("player_quit", function(session, e)
    local arenaId = ba.playerUtil.getArena(e.player)
    if not arenaId and session then
      arenaId = session.arenaId
    end
    if arenaId then
      voteService.clearWaitingVote(arenaId, e.player)
    end
    if session then
      voteService.clearActiveVote(session, e.player)
    end
  end)
end

return M

--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- LuckyPillarsVoteListener.java (the redundant /lucky_pillarsvote command entry point) IS ported below (player_command).
local gameManager = require("game_manager")
local voteService = require("support.vote_service")

local M = {}

function M.register()
  -- Mirrors legacy LuckyPillarsVoteListener: /lucky_pillarsvote is a second entry point into the same vote system as the waiting item.
  ba.events.on("player_command", function(session, e)
    local message = e.message
    if not message or message == "" then return end
    local trimmed = message:match("^%s*(.-)%s*$")
    local prefix = "/lucky_pillarsvote"
    if trimmed:lower():sub(1, #prefix) ~= prefix then return end
    e:cancel()
    local rest = message:sub(2):match("^%s*(.-)%s*$")
    local parts = {}
    for word in rest:gmatch("%S+") do parts[#parts + 1] = word end
    local args = {}
    for i = 2, #parts do args[#args + 1] = parts[i] end
    voteService.handleVoteAction(e.player, args)
  end)

  ba.events.on("player_move", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end
    if session.phase() ~= "PLAYING" then
      return
    end
    if not session.isInsideBounds(e.to) then
      gameManager.handleNonCombatDeath(session, e.player)
    end
  end)

  ba.events.on("block_break", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end
    if session.phase() ~= "PLAYING" then
      e:cancel()
      return
    end
    if session.state.blockBreakingDisabled then
      e:cancel()
      session.messages.sendRaw(e.player, session.config.translation(e.player, "messages.block_breaking_disabled"))
      return
    end
    if not session.isInsideBounds(e.location) then
      e:cancel()
    end
  end)

  ba.events.on("block_place", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end
    if session.phase() ~= "PLAYING" then
      e:cancel()
      return
    end
    if session.state.lavaFrontY and e.location.y <= session.state.lavaFrontY then
      e:cancel()
      session.messages.sendRaw(e.player, session.config.translation(e.player, "messages.block_placing_below_lava"))
      return
    end
    if not session.isInsideBounds(e.location) then
      e:cancel()
    end
  end)

  ba.events.on("player_damage_by_entity", function(session, e)
    if not session.isPlaying(e.target) then
      return
    end
    if session.phase() ~= "PLAYING" then
      e:cancel()
      return
    end
    if not e.damager or not session.isPlaying(e.damager) then
      e:cancel()
      return
    end

    if session.teams.isEnabled() then
      local attackerTeam = session.teams.forPlayer(e.damager)
      local targetTeam = session.teams.forPlayer(e.target)
      if attackerTeam and targetTeam and attackerTeam.id:lower() == targetTeam.id:lower() then
        e:cancel()
        return
      end
    end

    gameManager.recordHit(session, e.target, e.damager)

    local finalHealth = session.player.health(e.target) - e.finalDamage
    if finalHealth > 0 then
      return
    end

    e:cancel()
    gameManager.handleKill(session, e.damager, e.target)
  end)

  ba.events.on("player_damage", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end
    if session.phase() ~= "PLAYING" then
      e:cancel()
      return
    end

    if e.cause == "FALL" and session.state.fallProtectionUntil[e.player] and os.clock() <= session.state.fallProtectionUntil[e.player] then
      e:cancel()
      return
    end

    local finalHealth = session.player.health(e.player) - e.finalDamage
    if finalHealth > 0 then
      return
    end

    e:cancel()
    gameManager.handleNonCombatDeath(session, e.player)
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

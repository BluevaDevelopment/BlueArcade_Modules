-- Mirrors legacy CaptureTheWoolListener.java. CaptureTheWoolVoteListener.java (the redundant
-- /capture_the_woolvote PlayerCommandPreprocessEvent entry point) IS ported below (player_command).
local woolService = require("support.wool_service")
local armoryService = require("support.armory_service")
local gameManager = require("game_manager")
local voteService = require("support.vote_service")

local M = {}

function M.register()
  -- Mirrors legacy CaptureTheWoolVoteListener: /capture_the_woolvote is a second entry point into the same vote system as the waiting item.
  ba.events.on("player_command", function(session, e)
    local message = e.message
    if not message or message == "" then return end
    local trimmed = message:match("^%s*(.-)%s*$")
    local prefix = "/capture_the_woolvote"
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

    if gameManager.isInRestrictedZone(session, e.player, e.to) then
      e:cancel()
      session.messages.sendRaw(e.player, session.config.translation(e.player, "messages.restricted_zone"))
      return
    end

    if not session.isInsideBounds(e.to) then
      gameManager.handleNonCombatDeath(session, e.player)
    end
  end)

  -- Mirrors legacy's HIGHEST-priority right-click-block check: any real Container the player
  -- right-clicks opens a read-only clone (ArmoryService), not just chests specifically.
  ba.events.on("player_interact", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end
    if session.phase() ~= "PLAYING" then
      return
    end
    if e.action ~= "RIGHT_CLICK_BLOCK" or not e.clickedBlockLocation then
      return
    end

    local loc = e.clickedBlockLocation
    local x, y, z = math.floor(loc.x), math.floor(loc.y), math.floor(loc.z)
    if armoryService.openChestClone(session, e.player, x, y, z) then
      e:cancel()
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

    local x, y, z = math.floor(e.location.x), math.floor(e.location.y), math.floor(e.location.z)

    if woolService.isWoolSpawnLocation(session, x, y, z) then
      local picked = gameManager.handleWoolPickup(session, e.player, x, y, z)
      if picked then
        e:allow()
        e.setDropItems(false)
      else
        e:cancel()
        local blocked = gameManager.getWoolPickupBlockedMessage(session, e.player, x, y, z)
        if blocked and blocked ~= "" then
          session.messages.sendRaw(e.player, blocked)
        end
      end
      return
    end

    if woolService.isCaptureLocation(session, x, y, z) then
      e:cancel()
      return
    end

    if not session.isInsideBounds(e.location) or not gameManager.canBreakBlock(session, x, y, z) then
      e:cancel()
      return
    end

    e:allow()
    gameManager.untrackPlacedBlock(session, x, y, z)
  end)

  ba.events.on("block_place", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end
    if session.phase() ~= "PLAYING" then
      e:cancel()
      return
    end

    local x, y, z = math.floor(e.location.x), math.floor(e.location.y), math.floor(e.location.z)

    if not session.isInsideBounds(e.location) then
      e:cancel()
      return
    end

    if woolService.isCaptureLocation(session, x, y, z) then
      local captured = gameManager.handleWoolCapture(session, e.player, x, y, z, e.blockType)
      if captured then
        e:allow()
      else
        e:cancel()
      end
      return
    end

    if woolService.isCarriedWoolMaterial(session, e.player, e.blockType)
        or (woolService.isPlayerCarryingWool(session, e.player) and woolService.isObjectiveWoolMaterial(session, e.blockType)) then
      e:cancel()
      return
    end

    if woolService.isWoolSpawnLocation(session, x, y, z) then
      e:cancel()
      return
    end

    e:allow()
    gameManager.trackPlacedBlock(session, x, y, z)
  end)

  ba.events.on("player_drop_item", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end
    if session.phase() ~= "PLAYING" then
      e:cancel()
      return
    end

    if woolService.isPlayerCarryingWool(session, e.player) and woolService.isObjectiveWoolMaterial(session, e.itemType) then
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

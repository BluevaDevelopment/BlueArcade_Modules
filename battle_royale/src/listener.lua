-- Mirrors legacy BattleRoyaleListener.java. onEntityExplode/onBlockExplode (explosion-triggered
-- chest loot) aren't ported - see support/loot_service.lua's own doc for why. player_interact's
-- real double-dispatch (once per hand) isn't explicitly filtered the way legacy filters
-- `event.getHand() != EquipmentSlot.HAND` - the chest is already AIR by the time the second
-- dispatch runs (both fire synchronously against the same live block), so the material-type check
-- alone naturally skips the second one; a genuinely harmless simplification, not a behavioral gap.
local gameManager = require("game_manager")
local lootService = require("support.loot_service")

local M = {}

local function isInteractiveBlock(materialName)
  return materialName:match("_DOOR$") or materialName:match("_BUTTON$")
    or materialName:match("_PRESSURE_PLATE$") or materialName:match("_TRAPDOOR$")
    or materialName == "LEVER"
end

function M.register()
  ba.events.on("player_move", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end
    if session.state.droppingPlayers[e.player] and session.player.isOnGround(e.player) then
      require("support.drop_service").handleLanding(session, e.player)
    end
  end)

  ba.events.on("player_toggle_sneak", function(session, e)
    if session.state.planePlayers[e.player] then
      require("support.drop_service").handlePlaneSneakToggle(session, e.player, e.sneaking)
    end
  end)

  ba.events.on("player_interact", function(session, e)
    local materialName = e.clickedBlockType
    if not materialName then
      return
    end

    if materialName == "CHEST" or materialName == "TRAPPED_CHEST" or materialName == "ENDER_CHEST" then
      if not session.isPlaying(e.player) then
        return
      end
      if session.phase() ~= "PLAYING" then
        e:cancel()
        return
      end

      local x, y, z = e.clickedBlockLocation.x, e.clickedBlockLocation.y, e.clickedBlockLocation.z
      if lootService.isPlayerPlacedBlock(session, x, y, z) then
        return
      end
      if lootService.isChestLooted(session, x, y, z) then
        e:cancel()
        return
      end

      e:cancel()
      lootService.handleChestLoot(session, e.player, x, y, z, materialName)
      return
    end

    if isInteractiveBlock(materialName) then
      return
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

    if session.config.getBoolean("block_rules.break_only_player_placed", false)
        and not lootService.isPlayerPlacedBlock(session, e.location.x, e.location.y, e.location.z) then
      e:cancel()
      return
    end

    if e.blockType == "CHEST" or e.blockType == "TRAPPED_CHEST" or e.blockType == "ENDER_CHEST" then
      if not lootService.isPlayerPlacedBlock(session, e.location.x, e.location.y, e.location.z) then
        e:cancel()
        lootService.handleChestLoot(session, e.player, e.location.x, e.location.y, e.location.z, e.blockType)
        return
      end
    end

    if not gameManager.hasRespawnRegion(session) then
      e:cancel()
      return
    end

    lootService.untrackPlacedBlock(session, e.location.x, e.location.y, e.location.z)
  end)

  ba.events.on("block_place", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end
    if session.phase() ~= "PLAYING" then
      e:cancel()
      return
    end
    if not gameManager.hasRespawnRegion(session) then
      e:cancel()
      return
    end
    lootService.trackPlacedBlock(session, e.location.x, e.location.y, e.location.z)
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

    if session.state.gracePeriodUntilClock and os.clock() < session.state.gracePeriodUntilClock then
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

    if session.state.droppingPlayers[e.player] then
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
end

return M

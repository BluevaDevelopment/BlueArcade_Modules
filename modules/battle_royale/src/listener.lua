--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- player_interact's per-hand double-dispatch self-filters: the chest is already AIR by hand two.
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

  -- Mirrors legacy BattleRoyaleGame.handleChestExplosion: TNT/creepers still fill chests before destroying them.
  ba.events.on("entity_explode", function(session, e)
    if session.phase() ~= "PLAYING" or not session.isInsideBounds(e.location) then return end

    local breakOnlyPlaced = session.config.getBoolean("block_rules.break_only_player_placed", false)
    for i = e.blockCount, 1, -1 do
      local blockLoc = e.blockLocationAt(i)
      if blockLoc then
        local x, y, z = math.floor(blockLoc.x), math.floor(blockLoc.y), math.floor(blockLoc.z)
        local survives = true
        if breakOnlyPlaced then
          if lootService.isPlayerPlacedBlock(session, x, y, z) then
            lootService.untrackPlacedBlock(session, x, y, z)
          else
            e.removeBlock(blockLoc)
            survives = false
          end
        end

        if survives then
          local blockType = session.world.blockTypeAt(x, y, z)
          if blockType == "CHEST" or blockType == "TRAPPED_CHEST" or blockType == "ENDER_CHEST" then
            lootService.handleChestLoot(session, nil, x, y, z, blockType)
          end
        end
      end
    end
  end)
end

return M

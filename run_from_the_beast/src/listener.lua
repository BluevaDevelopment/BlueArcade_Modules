-- Reset-wand/shredder-plate branches aren't ported - StoreAPI-gated, see game_manager.lua.
-- block_place isn't registered - legacy's onBlockPlace only ever handled shredder placement.
local gameManager = require("game_manager")
local checkpointService = require("support.checkpoint_service")
local armoryService = require("support.armory_service")

local M = {}

function M.register()
  ba.events.on("block_break", function(session, e)
    if session.isPlaying(e.player) then
      e:cancel()
    end
  end)

  ba.events.on("player_move", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end
    if e.from.x == e.to.x and e.from.y == e.to.y and e.from.z == e.to.z then
      return
    end

    if session.phase() == "COUNTDOWN" then
      e.setTo(e.from)
      return
    end

    if not session.isInsideBounds(e.to) then
      gameManager.handleOutOfBounds(session, e.player, false)
      return
    end

    local deathBlock = session.dataAccess.getGameDataString("basic.death_block") or "BARRIER"
    local below = session.world.blockTypeAt(math.floor(e.to.x), math.floor(e.to.y) - 1, math.floor(e.to.z))
    if below == deathBlock:upper() then
      gameManager.handleOutOfBounds(session, e.player, true)
    end
  end)

  ba.events.on("player_interact", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end
    -- Only the main hand - Bukkit fires a real PlayerInteractEvent once per hand for a single
    -- right-click, otherwise checkpoint set/return would double-fire per click.
    if e.hand ~= "HAND" then
      return
    end

    local itemType = session.player.itemInMainHandType(e.player)
    if itemType then
      if itemType == checkpointService.getCheckpointSetMaterial(session) then
        e:cancel()
        checkpointService.handleCheckpointSet(session, e.player)
        return
      end
      if itemType == checkpointService.getCheckpointReturnMaterial(session) then
        e:cancel()
        checkpointService.handleCheckpointReturn(session, e.player)
        return
      end
    end

    if e.action == "RIGHT_CLICK_BLOCK" and e.clickedBlockLocation then
      local loc = e.clickedBlockLocation
      local x, y, z = math.floor(loc.x), math.floor(loc.y), math.floor(loc.z)
      if session.world.containerSizeAt(x, y, z) then
        e:cancel()
        armoryService.openArmory(session, e.player, x, y, z)
      end
    end
  end)

  ba.events.on("player_damage_by_entity", function(session, e)
    if not session.isPlaying(e.target) then
      return
    end
    if not e.damager or not session.isPlaying(e.damager) then
      return
    end

    local victimIsBeast = gameManager.isBeast(session, e.target)
    local damagerIsBeast = gameManager.isBeast(session, e.damager)
    if not victimIsBeast and not damagerIsBeast then
      e:cancel()
      return
    end

    local finalHealth = session.player.health(e.target) - e.finalDamage
    if finalHealth > 0 then
      return
    end

    e:cancel()
    gameManager.handleDamage(session, e.target, e.damager)
  end)

  ba.events.on("player_damage", function(session, e)
    if not session.isPlaying(e.player) then
      return
    end

    if e.cause == "FALL" then
      e:cancel()
      return
    end

    if e.cause == "VOID" then
      e:cancel()
      gameManager.handleOutOfBounds(session, e.player, false)
      return
    end

    local finalHealth = session.player.health(e.player) - e.finalDamage
    if finalHealth > 0 then
      return
    end

    e:cancel()
    gameManager.handleDamage(session, e.player, nil)
  end)

  ba.events.on("player_attack_entity", function(session, e)
    if session.state.beastDisguiseHandle and e.entity == session.state.beastDisguiseHandle then
      e:cancel()
      gameManager.handleDisguiseDamage(session, e.attacker, e.finalDamage)
    end
  end)

  ba.events.on("player_interact_entity", function(session, e)
    if session.state.beastDisguiseHandle and e.entity == session.state.beastDisguiseHandle then
      e:cancel()
    end
  end)
end

return M

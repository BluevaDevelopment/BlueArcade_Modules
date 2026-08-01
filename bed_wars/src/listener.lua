-- Mirrors legacy BedWarsListener.java. BedWarsVoteListener.java (a redundant command-preprocess
-- entry point) isn't ported - same as every prior converted module's vote_service.lua handling
-- votes purely through the menu-action/waiting-item path. `onPlayerInteractAtEntity` isn't ported
-- either - confirmed dead in the legacy source: `PlayerInteractAtEntityEvent` only fires for
-- entities with sub-hitboxes (ArmorStands), never a plain `Villager`, so `onPlayerInteractEntity`
-- alone already covers every real shop-NPC click. The Fireball-vs-fireball's-own-shooter damage
-- guard legacy has in `onDamage` isn't ported either - this module's own fireball special item
-- deals damage manually via config (`damage_self`/`damage_enemy`/`damage_teammates`, see
-- special_items_service.lua), through a world-sourced `world.createExplosion` call that doesn't
-- fire a real `EntityExplodeEvent`/`EntityDamageByEntityEvent` for the fireball itself the way a
-- genuinely exploding entity would - there is nothing for that guard to prevent here.
local gameManager = require("game_manager")
local bedService = require("support.bed_service")
local npcService = require("support.npc_service")
local armoryService = require("support.armory_service")
local shopService = require("support.shop_service")
local upgradeService = require("support.upgrade_service")
local voteService = require("support.vote_service")

local M = {}

local function openShopMenu(session, handle, npcDef)
  if npcDef.type == "STORE" then
    shopService.openShop(session, handle)
  else
    upgradeService.openUpgradesMenu(session, handle)
  end
end

local BED_SUFFIX = "_BED"
local function isBedMaterial(material)
  return material ~= nil and #material > #BED_SUFFIX and material:sub(-#BED_SUFFIX) == BED_SUFFIX
end

function M.register()
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

  ba.events.on("player_move", function(session, e)
    if not session.isPlaying(e.player) then return end
    if session.phase() ~= "PLAYING" then return end

    if gameManager.isInRestrictedZone(session, e.player, e.to) then
      e:cancel()
      session.messages.sendRaw(e.player, session.config.translation(e.player, "messages.restricted_zone"))
      return
    end

    if not session.isInsideBounds(e.to) then
      gameManager.handleNonCombatDeath(session, e.player)
    end
  end)

  ba.events.on("player_interact", function(session, e)
    if not session.isPlaying(e.player) then return end
    if session.phase() ~= "PLAYING" then return end
    if e.action ~= "RIGHT_CLICK_BLOCK" or not e.clickedBlockLocation then return end

    local loc = e.clickedBlockLocation
    local x, y, z = math.floor(loc.x), math.floor(loc.y), math.floor(loc.z)

    if e.clickedBlockType == "ENDER_CHEST" then
      e:cancel()
      gameManager.openArenaEnderChest(session, e.player)
      return
    end

    if armoryService.openChestClone(session, e.player, x, y, z) then
      e:cancel()
    end
  end)

  ba.events.on("player_interact_entity", function(session, e)
    if not session.isPlaying(e.player) then return end
    if session.phase() ~= "PLAYING" then return end

    local npcDef = npcService.getNpcDefinitionByHandle(session, e.entity)
    if npcDef then
      e:cancel()
      openShopMenu(session, e.player, npcDef)
    end
  end)

  -- The non-player-target half of NPC-attack protection (`player_damage_by_entity` below only
  -- fires for a Player target - a Villager shop NPC never is one), reusing the same shop-open
  -- behavior as a genuine right-click so accidentally left-clicking an NPC still opens its menu
  -- instead of just silently blocking the hit, matching legacy's own `onDamage` NPC branch.
  ba.events.on("player_attack_entity", function(session, e)
    if session.phase() ~= "PLAYING" then return end
    if not session.isPlaying(e.attacker) then return end

    local npcDef = npcService.getNpcDefinitionByHandle(session, e.entity)
    if npcDef then
      e:cancel()
      openShopMenu(session, e.attacker, npcDef)
    end
  end)

  ba.events.on("block_break", function(session, e)
    if not session.isPlaying(e.player) then return end

    if session.phase() ~= "PLAYING" then
      e:cancel()
      return
    end

    local x, y, z = math.floor(e.location.x), math.floor(e.location.y), math.floor(e.location.z)

    if gameManager.isBedLocation(session, x, y, z) then
      local bedDef = bedService.findBedAtLocation(session, x, y, z)
      if bedDef then
        if session.teams.isEnabled() then
          local hasPlayers = false
          for _, handle in ipairs(session.players()) do
            local pTeam = session.teams.forPlayer(handle)
            if pTeam and pTeam.id:lower() == bedDef.teamId:lower() then
              hasPlayers = true
              break
            end
          end
          if not hasPlayers then
            e:cancel()
            return
          end

          local breakerTeam = session.teams.forPlayer(e.player)
          if breakerTeam and breakerTeam.id:lower() == bedDef.teamId:lower() then
            e:cancel()
            local msg = session.config.translation(e.player, "messages.bed.cannot_break_own")
            if msg then
              session.messages.sendRaw(e.player, msg)
            end
            return
          end
        end

        e:cancel()
        gameManager.handleBedBreak(session, e.player, x, y, z)
      end
      return
    end

    if gameManager.isSpawnerLocation(session, x, y, z) then
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
    if not session.isPlaying(e.player) then return end

    if session.phase() ~= "PLAYING" then
      e:cancel()
      return
    end

    local x, y, z = math.floor(e.location.x), math.floor(e.location.y), math.floor(e.location.z)

    if not session.isInsideBounds(e.location) then
      e:cancel()
      return
    end

    if gameManager.isBedLocation(session, x, y, z) or gameManager.isSpawnerLocation(session, x, y, z) then
      e:cancel()
      return
    end

    e:allow()
    gameManager.trackPlacedBlock(session, x, y, z)
  end)

  ba.events.on("player_damage_by_entity", function(session, e)
    if e.target == nil or not session.isPlaying(e.target) then return end

    if session.phase() ~= "PLAYING" then
      e:cancel()
      return
    end

    if e.damager == nil or not session.isPlaying(e.damager) then
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
    if finalHealth > 0 then return end

    e:cancel()
    gameManager.handleKill(session, e.damager, e.target)
  end)

  ba.events.on("player_damage", function(session, e)
    if not session.isPlaying(e.player) then return end

    if session.phase() ~= "PLAYING" then
      e:cancel()
      return
    end

    if e.cause == "FALL" then
      local until_ = session.state.fallProtectionUntil[e.player]
      if until_ and os.clock() < until_ then
        e:cancel()
        return
      end
    end

    local finalHealth = session.player.health(e.player) - e.finalDamage
    if finalHealth > 0 then return end

    e:cancel()
    gameManager.handleNonCombatDeath(session, e.player)
  end)

  -- entity_explode - TNT (and any other genuinely exploding entity) only breaks player-placed
  -- blocks, never the map or beds, matching legacy `BedWarsListener.onEntityExplode`'s
  -- `blockList().removeIf`. Dispatched once per active session (see `dispatchByLocation`'s own
  -- doc) - `session.isInsideBounds` is this handler's own self-filter.
  ba.events.on("entity_explode", function(session, e)
    if not session.isInsideBounds(e.location) then return end
    for i = e.blockCount, 1, -1 do
      local blockLoc = e.blockLocationAt(i)
      if blockLoc then
        local x, y, z = math.floor(blockLoc.x), math.floor(blockLoc.y), math.floor(blockLoc.z)
        local key = x .. ":" .. y .. ":" .. z
        local breakable = session.state.playerPlacedBlocks[key] and not gameManager.isBedLocation(session, x, y, z)
        if breakable then
          session.state.playerPlacedBlocks[key] = nil
        else
          e.removeBlock(blockLoc)
        end
      end
    end
  end)

  -- item_spawn - prevents a broken bed's own dropped bed item from being picked back up, matching
  -- legacy `BedWarsListener.onItemSpawn`'s material-family check.
  ba.events.on("item_spawn", function(session, e)
    if not isBedMaterial(e.itemType) then return end
    if session.isInsideBounds(e.location) then
      e.cancel()
    end
  end)

  ba.events.on("inventory_close", function(session, e)
    shopService.onPlayerCloseShop(session, e.player)

    if e.trackingKey then
      local teamId = e.trackingKey:match("^bed_wars_ender_chest:.-:(.+)$")
      if teamId then
        gameManager.saveArenaEnderChest(session, teamId, e.contents)
      end
    end
  end)

  ba.events.on("inventory_click", function(session, e)
    if not session.isPlaying(e.player) then return end

    local hasPermanent = e.currentItemPermanentId ~= nil or e.cursorItemPermanentId ~= nil
    if hasPermanent then
      if e.clickedInventoryType ~= "PLAYER" or e.shiftClick then
        e:cancel()
        return
      end
    end

    if e.shiftClick and shopService.isPlayerInShop(session, e.player) then
      if shopService.handleShopShiftClick(session, e.player, e.rawSlot) then
        e:cancel()
      end
    end
  end)

  ba.events.on("inventory_drag", function(session, e)
    if not session.isPlaying(e.player) then return end
    if e.oldCursorPermanentId ~= nil and e.inventoryType ~= "PLAYER" then
      e:cancel()
    end
  end)

  ba.events.on("player_drop_item", function(session, e)
    if not session.isPlaying(e.player) then return end
    if e.itemPermanentId ~= nil then
      e:cancel()
    end
  end)
end

return M

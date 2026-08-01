-- Mirrors legacy BedWarsListener.java. `onPlayerInteractAtEntity` isn't ported - it's dead/redundant
-- in legacy (`PlayerInteractAtEntityEvent` never fires for a plain Villager). The Fireball-vs-own-shooter
-- damage guard isn't needed either - this module's fireball damages manually via config, which
-- never fires a real damage event for itself. BedWarsVoteListener.java IS ported below (player_command).
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
  -- Mirrors legacy BedWarsVoteListener: /bedwarsvote is a second entry point into the same vote system as the waiting item.
  ba.events.on("player_command", function(session, e)
    local message = e.message
    if not message or message == "" then return end
    local trimmed = message:match("^%s*(.-)%s*$")
    local prefix = "/bedwarsvote"
    if trimmed:lower():sub(1, #prefix) ~= prefix then return end
    e:cancel()
    local rest = message:sub(2):match("^%s*(.-)%s*$")
    local parts = {}
    for word in rest:gmatch("%S+") do parts[#parts + 1] = word end
    local args = {}
    for i = 2, #parts do args[#args + 1] = parts[i] end
    voteService.handleVoteAction(e.player, table.concat(args, " "))
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

    if armoryService.openContainer(session, e.player, x, y, z) then
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

  -- Non-player-target half of NPC-attack protection - left-clicking a shop NPC opens its menu
  -- instead of just blocking the hit, matching legacy's own `onDamage` NPC branch.
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

  -- TNT (and any other exploding entity) only breaks player-placed blocks, never the map or beds.
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

  -- Prevents a broken bed's own dropped bed item from being picked back up.
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

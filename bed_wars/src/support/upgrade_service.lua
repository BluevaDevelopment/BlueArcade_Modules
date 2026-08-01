--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy TeamUpgradeService.java - same shape as the shop, one level simpler (flat menu,
-- per-team progress). Bedrock half not ported. `applyAction` appends to the same
-- `session.state.teamXEnchantments`/`teamEffects` tables `game_manager.respawnPlayer` reads on
-- respawn, and also applies immediately to every online teammate.
local ROMAN = { "I", "II", "III", "IV", "V" }
local RESOURCE_CURRENCY = { iron = "IRON_INGOT", gold = "GOLD_INGOT", diamond = "DIAMOND", emerald = "EMERALD" }

local M = {}

local upgrades = nil -- lazily-loaded, module-scoped: ordered list of {id, icon, amount, name, lore, slot, tiers}
local menuSize = 27
local emptyItem = nil

local function normalizeMenuSize(configured)
  local size = math.max(9, math.min(54, configured))
  if size % 9 == 0 then return size end
  return (math.floor(size / 9) + 1) * 9
end

local function parseCurrency(raw)
  return RESOURCE_CURRENCY[(raw or "diamond"):lower()] or "IRON_INGOT"
end

local function loadUpgrades()
  if upgrades then return upgrades end

  menuSize = normalizeMenuSize(ba.config.getIntFrom("upgrades.yml", "menu_size", 27))
  emptyItem = {
    material = ba.config.getStringFrom("upgrades.yml", "empty_item.item_stack.material", "BLACK_STAINED_GLASS_PANE"),
    amount = math.max(1, ba.config.getIntFrom("upgrades.yml", "empty_item.item_stack.amount", 1)),
    name = ba.config.getStringFrom("upgrades.yml", "empty_item.name", " "),
    lore = ba.config.getStringListFrom("upgrades.yml", "empty_item.lore"),
  }

  upgrades = {}
  local upgIndex = 1
  while true do
    local base = "team_upgrades.upgrades." .. upgIndex
    local id = ba.config.getStringFrom("upgrades.yml", base .. ".id")
    if not id then break end

    local tiers = {}
    local tierIndex = 1
    while true do
      local tierBase = base .. ".tiers." .. tierIndex
      local cost = ba.config.getIntFrom("upgrades.yml", tierBase .. ".cost", -1)
      if cost < 0 then break end
      local actions = {}
      local actionIndex = 1
      while true do
        local action = ba.config.getStringFrom("upgrades.yml", tierBase .. ".actions." .. actionIndex)
        if not action then break end
        actions[#actions + 1] = action
        actionIndex = actionIndex + 1
      end
      tiers[#tiers + 1] = {
        tierIndex = tierIndex, cost = cost,
        currency = parseCurrency(ba.config.getStringFrom("upgrades.yml", tierBase .. ".currency", "diamond")),
        actions = actions,
      }
      tierIndex = tierIndex + 1
    end

    upgrades[#upgrades + 1] = {
      id = id,
      icon = ba.config.getStringFrom("upgrades.yml", base .. ".icon", "STONE"),
      amount = math.max(1, ba.config.getIntFrom("upgrades.yml", base .. ".amount", 1)),
      name = ba.config.getStringFrom("upgrades.yml", base .. ".name", id),
      lore = ba.config.getStringListFrom("upgrades.yml", base .. ".lore"),
      slot = math.max(0, math.min(menuSize - 1, ba.config.getIntFrom("upgrades.yml", base .. ".slot", upgIndex - 1))),
      tiers = tiers,
    }
    upgIndex = upgIndex + 1
  end

  return upgrades
end

local function findUpgrade(id)
  for _, upgrade in ipairs(loadUpgrades()) do
    if upgrade.id == id then return upgrade end
  end
  return nil
end

local function formatCurrencyName(session, handle, currency)
  if currency == "IRON_INGOT" then return session.config.translation(handle, "messages.shop.currencies.iron") or "Iron" end
  if currency == "GOLD_INGOT" then return session.config.translation(handle, "messages.shop.currencies.gold") or "Gold" end
  if currency == "DIAMOND" then return session.config.translation(handle, "messages.shop.currencies.diamond") or "Diamond" end
  if currency == "EMERALD" then return session.config.translation(handle, "messages.shop.currencies.emerald") or "Emerald" end
  return currency
end

local function menuText(path, fallback)
  return ba.config.getStringFrom("upgrades.yml", path, fallback)
end

local function getTeamTier(session, teamId, upgradeId)
  return session.state.upgradeTeamTiers[teamId .. ":" .. upgradeId] or 0
end

local function setTeamTier(session, teamId, upgradeId, tier)
  session.state.upgradeTeamTiers[teamId .. ":" .. upgradeId] = tier
end

local function buildUpgradeDefinition(session, handle, upgrade)
  local currentTier = 0
  if session.teams.isEnabled() then
    local team = session.teams.forPlayer(handle)
    if team then
      currentTier = getTeamTier(session, team.id:lower(), upgrade.id)
    end
  end

  local maxed = currentTier >= #upgrade.tiers
  local canAfford = false
  if not maxed then
    local next = upgrade.tiers[currentTier + 1]
    canAfford = session.player.countItem(handle, next.currency) >= next.cost
  end

  local color = maxed and "<aqua>" or (canAfford and "<green>" or "<red>")
  local displayName = color .. upgrade.name

  local lore = {}
  for _, line in ipairs(upgrade.lore) do lore[#lore + 1] = line end
  for i, tier in ipairs(upgrade.tiers) do
    local tierColor = (i - 1) < currentTier and "<green>" or ((i - 1) == currentTier and "<yellow>" or "<gray>")
    lore[#lore + 1] = menuText("templates.content.tier_line", "{color}Tier {tier} <gray>- {cost} {currency}</gray>")
      :gsub("{color}", tierColor):gsub("{tier}", ROMAN[i] or tostring(i))
      :gsub("{cost}", tostring(tier.cost)):gsub("{currency}", formatCurrencyName(session, handle, tier.currency))
  end

  if maxed then
    lore[#lore + 1] = menuText("templates.content.maxed_line", "<aqua>MAXED OUT</aqua>")
  elseif canAfford then
    lore[#lore + 1] = menuText("templates.content.click_to_purchase_line", "<green>Click to purchase!</green>")
  else
    lore[#lore + 1] = menuText("templates.content.not_enough_resources_line", "<red>Not enough resources!</red>")
  end

  return {
    slot = upgrade.slot, material = upgrade.icon, amount = upgrade.amount, name = displayName, lore = lore,
    actions = { "MODULE;bed_wars;upgrade:" .. upgrade.id },
  }
end

function M.openUpgradesMenu(session, handle)
  local list = loadUpgrades()
  if #list == 0 then
    local msg = session.config.translation(handle, "messages.upgrade.not_configured") or "<red>Upgrades are not configured.</red>"
    session.messages.sendRaw(handle, msg)
    return
  end

  local items = {}
  for i = 0, menuSize - 1 do
    items[#items + 1] = { slot = i, material = emptyItem.material, amount = emptyItem.amount, name = emptyItem.name, lore = emptyItem.lore, actions = {} }
  end
  for _, upgrade in ipairs(list) do
    items[#items + 1] = buildUpgradeDefinition(session, handle, upgrade)
  end

  local title = ba.config.getStringFrom("upgrades.yml", "menu_name", "<dark_gray>Team Upgrades")
  session.menu.open(handle, title, menuSize, items, {})
end

local function applyAction(session, team, action)
  local type, data = action:match("^([^:]+):(.*)$")
  if not type then return end
  type = type:lower()
  local teamId = team.id:lower()

  local teamMembers = {}
  for _, handle in ipairs(session.players()) do
    local pTeam = session.teams.forPlayer(handle)
    if pTeam and pTeam.id:lower() == teamId then
      teamMembers[#teamMembers + 1] = handle
    end
  end

  if type == "player-effect" then
    local parts = {}
    for p in data:gmatch("[^,]+") do parts[#parts + 1] = p end
    if #parts >= 3 then
      local amplifier = tonumber(parts[2])
      local duration = tonumber(parts[3])
      if duration and duration <= 0 then duration = 2000000000 end
      if amplifier and duration then
        session.state.teamEffects[teamId] = session.state.teamEffects[teamId] or {}
        table.insert(session.state.teamEffects[teamId], { type = parts[1]:upper(), duration = duration, amplifier = amplifier })
        for _, handle in ipairs(teamMembers) do
          session.player.addPotionEffect(handle, parts[1], duration, amplifier, true, true)
        end
      end
    end
  elseif type == "generator-speed" then
    local parts = {}
    for p in data:gmatch("[^,]+") do parts[#parts + 1] = p end
    if #parts >= 2 then
      local genType = parts[1]:lower()
      local multiplier = tonumber(parts[2])
      if multiplier and (genType == "iron" or genType == "gold" or genType == "diamond" or genType == "emerald") then
        local spawnerService = require("support.spawner_service")
        spawnerService.setTeamSpawnerMultiplier(session, teamId, genType, multiplier)
      end
    end
  elseif type == "enchant-team" then
    local parts = {}
    for p in data:gmatch("[^,]+") do parts[#parts + 1] = p end
    if #parts >= 3 then
      local encName = parts[1]:lower()
      local level = tonumber(parts[2])
      local target = parts[3]:lower()
      if level and (target == "sword" or target == "armor" or target == "bow" or target == "pickaxe" or target == "axe") then
        local listKey = target == "sword" and "teamSwordEnchantments" or (target == "armor" and "teamArmorEnchantments" or (target == "bow" and "teamBowEnchantments" or nil))
        if listKey then
          session.state[listKey][teamId] = session.state[listKey][teamId] or {}
          table.insert(session.state[listKey][teamId], { name = encName, level = level })
        end
        for _, handle in ipairs(teamMembers) do
          session.player.enchantEquipped(handle, target, encName, level)
        end
      end
    end
  end
end

local function purchaseUpgrade(session, handle, upgrade)
  if not session.teams.isEnabled() then
    session.messages.sendRaw(handle, session.config.translation(handle, "messages.upgrade.teams_disabled") or "<red>Teams are not enabled.</red>")
    return false
  end
  local team = session.teams.forPlayer(handle)
  if not team then
    session.messages.sendRaw(handle, session.config.translation(handle, "messages.upgrade.no_team") or "<red>You are not in a team.</red>")
    return false
  end

  local teamId = team.id:lower()
  local currentTier = getTeamTier(session, teamId, upgrade.id)
  if currentTier >= #upgrade.tiers then
    session.messages.sendRaw(handle, session.config.translation(handle, "messages.upgrade.maxed") or "<red>This upgrade is already maxed out.</red>")
    session.sounds.playDirect(handle, "BLOCK_NOTE_BLOCK_BASS", 1.0, 1.0)
    return false
  end

  local nextTier = upgrade.tiers[currentTier + 1]
  local money = session.player.countItem(handle, nextTier.currency)
  if money < nextTier.cost then
    local msg = session.config.translation(handle, "messages.shop.insufficient_money")
    if msg then
      msg = msg:gsub("{price}", tostring(nextTier.cost)):gsub("{currency}", formatCurrencyName(session, handle, nextTier.currency))
      session.messages.sendRaw(handle, msg)
    end
    session.sounds.playDirect(handle, "BLOCK_NOTE_BLOCK_BASS", 1.0, 1.0)
    return false
  end

  session.player.removeItem(handle, nextTier.currency, nextTier.cost)
  setTeamTier(session, teamId, upgrade.id, currentTier + 1)

  for _, action in ipairs(nextTier.actions) do
    applyAction(session, team, action)
  end

  local msg = session.config.translation(handle, "messages.upgrade.purchased")
  if msg then
    msg = msg:gsub("{player}", session.player.name(handle)):gsub("{upgrade}", upgrade.name):gsub("{tier}", tostring(currentTier + 1))
    for _, memberHandle in ipairs(session.players()) do
      local pTeam = session.teams.forPlayer(memberHandle)
      if pTeam and pTeam.id:lower() == teamId then
        session.messages.sendRaw(memberHandle, msg)
      end
    end
  end
  session.sounds.playDirect(handle, "BLOCK_NOTE_BLOCK_PLING", 1.0, 2.0)
  return true
end

function M.handleAction(session, handle, payload)
  local upgradeId = payload:match("^upgrade:(.+)$")
  if not upgradeId then return false end
  local upgrade = findUpgrade(upgradeId)
  if not upgrade then return false end

  purchaseUpgrade(session, handle, upgrade)
  M.openUpgradesMenu(session, handle)
  return true
end

function M.clearArena(session)
  session.state.upgradeTeamTiers = {}
end

return M

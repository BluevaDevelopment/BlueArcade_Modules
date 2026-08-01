-- Mirrors legacy ShopServiceImpl.java: a category->content->tier->buy_item interpreter reading
-- `shop.yml` at runtime, loaded once lazily at module scope (shared across arenas) via `ba.config`.
-- Not ported: the Bedrock half (unreachable), Quick Buy shift-click *customization* (no
-- PersistentPlayerDataAPI binding - Quick Buy still shows the server-configured defaults), Vault
-- currency (unbound, always resolves to 0 money; the shipped shop.yml never uses it), and legacy's
-- multi-path config-key fallback chains (this conversion's shop.yml only has one schema).
local RESOURCE_CURRENCY = { iron = "IRON_INGOT", gold = "GOLD_INGOT", diamond = "DIAMOND", emerald = "EMERALD" }
local SWORD_DAMAGE = { WOODEN_SWORD = 4, GOLDEN_SWORD = 4, STONE_SWORD = 5, IRON_SWORD = 6, DIAMOND_SWORD = 7, NETHERITE_SWORD = 8 }
local DYE_COLOR = {
  red = "RED", blue = "BLUE", green = "GREEN", yellow = "YELLOW", aqua = "CYAN", cyan = "CYAN",
  white = "WHITE", black = "BLACK", gray = "GRAY", grey = "GRAY", dark_gray = "GRAY", dark_grey = "GRAY",
  light_purple = "MAGENTA", magenta = "MAGENTA", pink = "PINK", orange = "ORANGE", gold = "ORANGE",
  lime = "LIME", brown = "BROWN", light_blue = "LIGHT_BLUE", purple = "PURPLE",
}
local ROMAN = { "I", "II", "III", "IV", "V" }

local M = {}

local shop = nil -- lazily-loaded, module-scoped catalog: { menuSize, maxIndexScan, ..., categories = {ordered list}, quickBuyDefaults = {list} }

local function normalizeMenuSize(configured)
  local size = math.max(9, math.min(54, configured))
  if size % 9 == 0 then return size end
  return (math.floor(size / 9) + 1) * 9
end

local function addSlotsFromRaw(raw, slots, seen, menuSize)
  if not raw or raw == "" then return end
  for part in raw:gmatch("[^,]+") do
    local trimmed = part:match("^%s*(.-)%s*$")
    local slot = tonumber(trimmed)
    if slot and slot >= 0 and slot < menuSize and not seen[slot] then
      seen[slot] = true
      slots[#slots + 1] = slot
    end
  end
end

local function parseSlotList(path, menuSize, fallback)
  local slots, seen = {}, {}
  local rawList = ba.config.getStringListFrom("shop.yml", path)
  if #rawList > 0 then
    for _, raw in ipairs(rawList) do
      addSlotsFromRaw(raw, slots, seen, menuSize)
    end
  else
    addSlotsFromRaw(ba.config.getStringFrom("shop.yml", path), slots, seen, menuSize)
  end
  if #slots == 0 then return fallback end
  return slots
end

local function resolveDynamicSlot(path, index, slots, fallback, menuSize)
  local raw = ba.config.getStringFrom("shop.yml", path)
  if raw and raw ~= "" then
    local configured = tonumber(raw)
    if configured and configured >= 0 and configured < menuSize then
      return configured
    end
  end
  if index >= 0 and index < #slots then
    return slots[index + 1]
  end
  return fallback
end

local function parseCurrency(raw)
  local key = (raw or "iron"):lower()
  if key == "vault" then return nil end
  return RESOURCE_CURRENCY[key] or "IRON_INGOT"
end

local function capitalizeItemName(raw)
  if not raw or raw == "" then return "" end
  local words = {}
  for word in raw:gsub("_", " "):gmatch("%S+") do
    words[#words + 1] = word:sub(1, 1):upper() .. word:sub(2):lower()
  end
  return table.concat(words, " ")
end

local function loadShop()
  if shop then return shop end

  local menuSize = normalizeMenuSize(ba.config.getIntFrom("shop.yml", "menu_size", 54))
  local maxIndexScan = math.max(1, ba.config.getIntFrom("shop.yml", "shop.settings.max_index_scan", 256))
  local contentSlots = parseSlotList("dynamic_slots", menuSize, { 19, 20, 21, 22, 23, 24, 25, 28, 29, 30, 31, 32, 33, 34, 37, 38, 39, 40, 41, 42, 43 })

  shop = {
    menuSize = menuSize,
    maxIndexScan = maxIndexScan,
    quickBuyButtonMaterial = ba.config.getStringFrom("shop.yml", "items.quick_buy.item_stack.material", "NETHER_STAR"),
    quickBuyButtonAmount = math.max(1, ba.config.getIntFrom("shop.yml", "items.quick_buy.item_stack.amount", 1)),
    quickBuyButtonSlot = math.max(0, math.min(menuSize - 1, ba.config.getIntFrom("shop.yml", "items.quick_buy.slot", 0))),
    separatorRegular = ba.config.getStringFrom("shop.yml", "templates.navigation.separator_regular.item_stack.material", "GRAY_STAINED_GLASS_PANE"),
    separatorSelected = ba.config.getStringFrom("shop.yml", "templates.navigation.separator_selected.item_stack.material", "GREEN_STAINED_GLASS_PANE"),
    quickBuyEmpty = ba.config.getStringFrom("shop.yml", "templates.quick_buy.empty.item_stack.material", "RED_STAINED_GLASS_PANE"),
    categorySlots = parseSlotList("templates.category.dynamic_slots", menuSize, { 1, 2, 3, 4, 5, 6, 7 }),
    contentSlots = contentSlots,
    quickBuySlots = parseSlotList("templates.quick_buy.dynamic_slots", menuSize, contentSlots),
    separatorSlots = parseSlotList("shop.settings.separator_slots", menuSize, { 9, 10, 11, 12, 13, 14, 15, 16, 17 }),
    categories = {},
    quickBuyDefaults = {},
  }

  for qbIndex = 1, maxIndexScan do
    local qbBase = "shop.quick_buy_defaults." .. qbIndex
    local category = ba.config.getStringFrom("shop.yml", qbBase .. ".category")
    if category then
      local content = ba.config.getStringFrom("shop.yml", qbBase .. ".content")
      local slot = resolveDynamicSlot(qbBase .. ".slot", qbIndex - 1, shop.quickBuySlots, 0, menuSize)
      if content then
        shop.quickBuyDefaults[#shop.quickBuyDefaults + 1] = { categoryId = category, contentId = content, slot = slot }
      end
    end
  end

  for catIndex = 1, maxIndexScan do
    local catBase = "shop.categories." .. catIndex
    local id = ba.config.getStringFrom("shop.yml", catBase .. ".id")
    if id then
      local category = {
        id = id,
        icon = ba.config.getStringFrom("shop.yml", catBase .. ".icon", "STONE"),
        name = ba.config.getStringFrom("shop.yml", catBase .. ".name", id),
        amount = math.max(1, ba.config.getIntFrom("shop.yml", catBase .. ".amount", 1)),
        slot = resolveDynamicSlot(catBase .. ".slot", catIndex - 1, shop.categorySlots, catIndex, menuSize),
        lore = ba.config.getStringListFrom("shop.yml", catBase .. ".lore"),
        content = {},
      }

      for contentIndex = 1, maxIndexScan do
        local contentBase = catBase .. ".content." .. contentIndex
        local contentId = ba.config.getStringFrom("shop.yml", contentBase .. ".id")
        if contentId then
          local content = {
            id = contentId,
            slot = resolveDynamicSlot(contentBase .. ".slot", contentIndex - 1, shop.contentSlots, 0, menuSize),
            name = ba.config.getStringFrom("shop.yml", contentBase .. ".name") or capitalizeItemName(contentId),
            lore = ba.config.getStringListFrom("shop.yml", contentBase .. ".lore"),
            permanent = ba.config.getBooleanFrom("shop.yml", contentBase .. ".permanent", false),
            downgradable = ba.config.getBooleanFrom("shop.yml", contentBase .. ".downgradable", false),
            unbreakable = ba.config.getBooleanFrom("shop.yml", contentBase .. ".unbreakable", false),
            weight = ba.config.getIntFrom("shop.yml", contentBase .. ".weight", 0),
            actions = ba.config.getStringListFrom("shop.yml", contentBase .. ".actions"),
            tiers = {},
          }

          for tierIndex = 1, maxIndexScan do
            local tierBase = contentBase .. ".tiers." .. tierIndex
            local materialStr = ba.config.getStringFrom("shop.yml", tierBase .. ".material")
            if materialStr then
              local buyItems = {}
              for biIndex = 1, maxIndexScan do
                local biBase = tierBase .. ".buy_items." .. biIndex
                local biMaterial = ba.config.getStringFrom("shop.yml", biBase .. ".material")
                if biMaterial then
                  local enchantments = {}
                  for encIndex = 1, maxIndexScan do
                    local enc = ba.config.getStringFrom("shop.yml", biBase .. ".enchantments." .. encIndex)
                    if enc then enchantments[#enchantments + 1] = enc end
                  end
                  local effects = {}
                  for effIndex = 1, maxIndexScan do
                    local eff = ba.config.getStringFrom("shop.yml", biBase .. ".effects." .. effIndex)
                    if eff then effects[#effects + 1] = eff end
                  end
                  buyItems[#buyItems + 1] = {
                    material = biMaterial:upper(),
                    amount = ba.config.getIntFrom("shop.yml", biBase .. ".amount", 1),
                    name = ba.config.getStringFrom("shop.yml", biBase .. ".name"),
                    lore = ba.config.getStringListFrom("shop.yml", biBase .. ".lore"),
                    autoEquip = ba.config.getBooleanFrom("shop.yml", biBase .. ".auto_equip", false),
                    special = ba.config.getStringFrom("shop.yml", biBase .. ".special"),
                    potionColor = ba.config.getStringFrom("shop.yml", biBase .. ".potion_color"),
                    actions = ba.config.getStringListFrom("shop.yml", biBase .. ".actions"),
                    enchantments = enchantments,
                    effects = effects,
                  }
                end
              end
              content.tiers[#content.tiers + 1] = {
                tierIndex = tierIndex,
                material = materialStr:upper(),
                amount = ba.config.getIntFrom("shop.yml", tierBase .. ".amount", 1),
                enchanted = ba.config.getBooleanFrom("shop.yml", tierBase .. ".enchanted", false),
                price = ba.config.getIntFrom("shop.yml", tierBase .. ".price", 1),
                currency = parseCurrency(ba.config.getStringFrom("shop.yml", tierBase .. ".currency", "iron")),
                buyItems = buyItems,
                actions = ba.config.getStringListFrom("shop.yml", tierBase .. ".actions"),
              }
            end
          end

          if #content.tiers > 0 then
            category.content[#category.content + 1] = content
          end
        end
      end

      table.sort(category.content, function(a, b) return a.slot < b.slot end)
      shop.categories[#shop.categories + 1] = category
    end
  end

  return shop
end

local function findCategory(catalog, categoryId)
  for _, cat in ipairs(catalog.categories) do
    if cat.id == categoryId then return cat end
  end
  return nil
end

local function findContent(category, contentId)
  for _, content in ipairs(category.content) do
    if content.id == contentId then return content end
  end
  return nil
end

local function getCache(session, handle)
  local cache = session.state.shopCache[handle]
  if not cache then
    cache = { tiers = {}, permanentItems = {}, categoryWeights = {} }
    session.state.shopCache[handle] = cache
  end
  return cache
end

local function calculateMoney(session, handle, currency)
  if not currency then return 0 end -- Vault gap, see file doc
  return session.player.countItem(handle, currency)
end

local function takeMoney(session, handle, currency, amount)
  if not currency then return end
  session.player.removeItem(handle, currency, amount)
end

local function formatCurrencyName(session, handle, currency)
  if not currency then return session.config.translation(handle, "messages.shop.currencies.money") or "Money" end
  if currency == "IRON_INGOT" then return session.config.translation(handle, "messages.shop.currencies.iron") or "Iron" end
  if currency == "GOLD_INGOT" then return session.config.translation(handle, "messages.shop.currencies.gold") or "Gold" end
  if currency == "DIAMOND" then return session.config.translation(handle, "messages.shop.currencies.diamond") or "Diamond" end
  if currency == "EMERALD" then return session.config.translation(handle, "messages.shop.currencies.emerald") or "Emerald" end
  return currency
end

local function getCurrencyColor(currency)
  if not currency then return "<white>" end
  if currency == "IRON_INGOT" then return "<white>" end
  if currency == "GOLD_INGOT" then return "<gold>" end
  if currency == "DIAMOND" then return "<aqua>" end
  if currency == "EMERALD" then return "<dark_green>" end
  return "<white>"
end

local function resolveDyeColor(teamId)
  return DYE_COLOR[(teamId or ""):lower()]
end

local function colorizeForTeam(session, handle, materialName)
  if materialName ~= "WHITE_WOOL" and materialName ~= "WHITE_STAINED_GLASS" then
    return materialName
  end
  if not session.teams.isEnabled() then return materialName end
  local team = session.teams.forPlayer(handle)
  if not team then return materialName end
  local dye = resolveDyeColor(team.id)
  if not dye then return materialName end
  local suffix = materialName == "WHITE_WOOL" and "_WOOL" or "_STAINED_GLASS"
  return dye .. suffix
end

local function resolveTeamId(session, handle)
  if not session.teams.isEnabled() then return "solo" end
  local team = session.teams.forPlayer(handle)
  return (team and team.id) or "solo"
end

local function parseEnchantments(list)
  local result = {}
  for _, raw in ipairs(list) do
    local name, level = raw:match("^([^:]+):(%d+)$")
    if name then
      result[#result + 1] = { name = name, level = tonumber(level) }
    end
  end
  return result
end

local function parseEffects(list)
  local result = {}
  for _, raw in ipairs(list) do
    local parts = {}
    for p in raw:gmatch("[^:]+") do parts[#parts + 1] = p end
    if #parts >= 3 then
      result[#result + 1] = { type = parts[1], duration = tonumber(parts[2]), amplifier = tonumber(parts[3]) }
    end
  end
  return result
end

local function removeWeakerSwords(session, handle, newSwordMaterial)
  local newDamage = SWORD_DAMAGE[newSwordMaterial] or 0
  for material, damage in pairs(SWORD_DAMAGE) do
    if damage <= newDamage then
      local count = session.player.countItem(handle, material)
      if count > 0 then
        session.player.removeItem(handle, material, count)
      end
    end
  end
end

local function giveBuyItem(session, handle, buyItem, content)
  local material = colorizeForTeam(session, handle, buyItem.material)
  local displayName = (buyItem.name and buyItem.name ~= "" and buyItem.name) or content.name
  if not displayName or displayName == "" then
    displayName = capitalizeItemName(content.id)
  end
  local lore = (#buyItem.lore > 0) and buyItem.lore or content.lore

  local teamId = resolveTeamId(session, handle)
  local teamEnchantments = {}
  if buyItem.autoEquip then
    teamEnchantments = session.state.teamArmorEnchantments[teamId] or {}
  elseif material == "BOW" then
    teamEnchantments = session.state.teamBowEnchantments[teamId] or {}
  elseif material:match("_SWORD$") or material:match("_AXE$") then
    teamEnchantments = session.state.teamSwordEnchantments[teamId] or {}
  end

  if material:match("_SWORD$") then
    removeWeakerSwords(session, handle, material)
  end

  session.player.giveShopItem(handle, material, buyItem.amount, -1, displayName, lore, {
    unbreakable = content.unbreakable,
    potionColorHex = buyItem.potionColor,
    enchantments = parseEnchantments(buyItem.enchantments),
    teamEnchantments = teamEnchantments,
    effects = parseEffects(buyItem.effects),
    autoEquip = buyItem.autoEquip,
    permanentId = content.permanent and content.id or nil,
    specialId = buyItem.special,
  })
end

local function applyActionPlaceholders(session, handle, input, category, content, tier)
  local teamId = resolveTeamId(session, handle)
  local result = input
    :gsub("{player}", session.player.name(handle))
    :gsub("{uuid}", handle)
    :gsub("{arena}", tostring(session.arenaId))
    :gsub("{arena_id}", tostring(session.arenaId))
    :gsub("{team}", teamId)
    :gsub("{category}", category.name)
    :gsub("{category_id}", category.id)
    :gsub("{item}", content.name)
    :gsub("{item_id}", content.id)
  if tier then
    result = result
      :gsub("{tier}", tostring(tier.tierIndex))
      :gsub("{price}", tostring(tier.price))
      :gsub("{currency}", formatCurrencyName(session, handle, tier.currency))
  end
  return result
end

local function runConfiguredActions(session, handle, category, content, tier, actions)
  if not actions or #actions == 0 then return end
  for _, rawAction in ipairs(actions) do
    if rawAction and rawAction ~= "" then
      local action = applyActionPlaceholders(session, handle, rawAction, category, content, tier)
      local type, data = action:match("^([^:]+):?(.*)$")
      type = type and type:lower() or ""
      if type == "message" then
        session.messages.sendRaw(handle, data)
      elseif type == "broadcast" then
        for _, p in ipairs(session.players()) do
          session.messages.sendRaw(p, data)
        end
      elseif type == "console" or type == "console-command" then
        session.player.runConsoleCommand(data)
      elseif type == "player" or type == "player-command" then
        session.player.runCommand(handle, data)
      elseif type == "sound" then
        local parts = {}
        for p in data:gmatch("[^:]+") do parts[#parts + 1] = p end
        if parts[1] then
          session.sounds.playDirect(handle, parts[1], tonumber(parts[2]) or 1.0, tonumber(parts[3]) or 1.0)
        end
      elseif type == "effect" or type == "potion-effect" then
        local parts = {}
        for p in data:gmatch("[^:]+") do parts[#parts + 1] = p end
        if #parts >= 3 then
          local ambient = parts[4] == "true"
          local particles = parts[5] == nil or parts[5] == "true"
          session.player.addPotionEffect(handle, parts[1], tonumber(parts[2]), tonumber(parts[3]), ambient, particles)
        end
      elseif type == "give" then
        local parts = {}
        for p in data:gmatch("[^:]+") do parts[#parts + 1] = p end
        if parts[1] then
          session.player.giveItem(handle, parts[1], math.max(1, tonumber(parts[2]) or 1), -1)
        end
      end
    end
  end
end

local function purchaseContent(session, handle, category, content)
  local catalog = loadShop()
  local cache = getCache(session, handle)
  local currentTierIndex = cache.tiers[content.id] or -1
  local nextTierIndex = currentTierIndex + 1

  if content.weight > 0 then
    local maxWeight = cache.categoryWeights[category.id] or -1
    if maxWeight >= 0 and content.weight < maxWeight then
      local msg = session.config.translation(handle, "messages.shop.weight_blocked") or "<red>You already have better armor!</red>"
      session.messages.sendRaw(handle, msg)
      session.sounds.playDirect(handle, "BLOCK_NOTE_BLOCK_BASS", 1.0, 1.0)
      return false
    end
  end

  if nextTierIndex >= #content.tiers then
    if content.permanent and cache.permanentItems[content.id] then
      local msg = session.config.translation(handle, "messages.shop.already_bought") or "<red>You already own this permanent item!</red>"
      session.messages.sendRaw(handle, msg)
      session.sounds.playDirect(handle, "BLOCK_NOTE_BLOCK_BASS", 1.0, 1.0)
      return false
    end
    nextTierIndex = currentTierIndex
  end

  local tier = content.tiers[nextTierIndex + 1]
  local money = calculateMoney(session, handle, tier.currency)
  if money < tier.price then
    local msg = session.config.translation(handle, "messages.shop.insufficient_money") or "<red>You don't have enough {currency}! Need {price} more.</red>"
    msg = msg:gsub("{price}", tostring(tier.price)):gsub("{currency}", formatCurrencyName(session, handle, tier.currency))
    session.messages.sendRaw(handle, msg)
    session.sounds.playDirect(handle, "BLOCK_NOTE_BLOCK_BASS", 1.0, 1.0)
    return false
  end

  if content.permanent and cache.permanentItems[content.id] then
    local msg = session.config.translation(handle, "messages.shop.already_bought") or "<red>You already own this permanent item!</red>"
    session.messages.sendRaw(handle, msg)
    session.sounds.playDirect(handle, "BLOCK_NOTE_BLOCK_BASS", 1.0, 1.0)
    return false
  end

  if currentTierIndex >= 0 and nextTierIndex > currentTierIndex then
    local oldTier = content.tiers[currentTierIndex + 1]
    for _, bi in ipairs(oldTier.buyItems) do
      local count = session.player.countItem(handle, bi.material)
      if count > 0 then
        session.player.removeItem(handle, bi.material, math.min(count, bi.amount))
      end
    end
  end

  takeMoney(session, handle, tier.currency, tier.price)
  for _, bi in ipairs(tier.buyItems) do
    giveBuyItem(session, handle, bi, content)
    runConfiguredActions(session, handle, category, content, tier, bi.actions)
  end

  cache.tiers[content.id] = nextTierIndex
  if content.permanent then
    cache.permanentItems[content.id] = true
  end
  if content.weight > 0 then
    cache.categoryWeights[category.id] = content.weight
  end

  local msg = session.config.translation(handle, "messages.shop.purchased") or "<green>You purchased {item}!</green>"
  session.messages.sendRaw(handle, applyActionPlaceholders(session, handle, msg, category, content, nil))
  session.sounds.playDirect(handle, "BLOCK_NOTE_BLOCK_PLING", 1.0, 2.0)
  runConfiguredActions(session, handle, category, content, tier, content.actions)
  runConfiguredActions(session, handle, category, content, tier, tier.actions)
  return true
end

local function menuText(path, fallback)
  return ba.config.getStringFrom("shop.yml", path, fallback)
end

local function buildContentDefinition(session, handle, cache, content)
  local currentTierIndex = cache.tiers[content.id] or -1
  local nextTierIndex = currentTierIndex + 1
  local isMaxedPermanent = content.permanent and nextTierIndex >= #content.tiers and cache.permanentItems[content.id]
  local maxed = isMaxedPermanent or (nextTierIndex >= #content.tiers and #content.tiers > 1)

  local displayTier
  if isMaxedPermanent then
    displayTier = content.tiers[currentTierIndex + 1]
  elseif nextTierIndex >= #content.tiers and not content.permanent then
    displayTier = content.tiers[currentTierIndex + 1]
  else
    displayTier = content.tiers[nextTierIndex + 1]
  end

  local canAfford = not maxed and calculateMoney(session, handle, displayTier.currency) >= displayTier.price
  local color = maxed and "<aqua>" or (canAfford and "<green>" or "<red>")
  local displayName = color .. content.name

  local lore = {}
  for _, line in ipairs(content.lore) do lore[#lore + 1] = line end

  if #content.tiers > 1 then
    for i, tier in ipairs(content.tiers) do
      local tierColor
      if (i - 1) < nextTierIndex then
        tierColor = "<green>"
      elseif (i - 1) == nextTierIndex and not maxed then
        tierColor = "<yellow>"
      else
        tierColor = "<gray>"
      end
      local line = menuText("templates.content.tier_line", "{color}Tier {tier} <gray>- {currency_color}{price} {currency}</gray>")
        :gsub("{color}", tierColor):gsub("{tier}", ROMAN[i] or tostring(i))
        :gsub("{currency_color}", getCurrencyColor(tier.currency)):gsub("{price}", tostring(tier.price))
        :gsub("{currency}", formatCurrencyName(session, handle, tier.currency))
      lore[#lore + 1] = line
    end
  else
    local tier = content.tiers[1]
    local line = menuText("templates.content.cost_line", "<gray>Cost: {currency_color}{price} {currency}</gray>")
      :gsub("{currency_color}", getCurrencyColor(tier.currency)):gsub("{price}", tostring(tier.price))
      :gsub("{currency}", formatCurrencyName(session, handle, tier.currency))
    lore[#lore + 1] = line
  end

  if maxed then
    lore[#lore + 1] = menuText("templates.content.maxed_line", "<aqua>MAXED OUT</aqua>")
  elseif canAfford then
    lore[#lore + 1] = menuText("templates.content.click_to_purchase_line", "<green>Click to purchase!</green>")
  else
    lore[#lore + 1] = menuText("templates.content.not_enough_resources_line", "<red>Not enough resources!</red>")
  end

  return {
    slot = content.slot,
    material = colorizeForTeam(session, handle, displayTier.material),
    amount = displayTier.amount,
    name = displayName,
    lore = lore,
    actions = { "MODULE;bed_wars;shop:buy:" .. content.id },
  }
end

local function buildNavigation(session, handle, activeCategory, catalog)
  local items = {}
  local qbActive = activeCategory == nil
  local qbName = qbActive and menuText("templates.quick_buy.tab_selected", "<yellow>Quick Buy</yellow>")
    or menuText("templates.quick_buy.tab", "<gray>Quick Buy</gray>")
  local qbLore = { qbActive and menuText("templates.navigation.selected_lore", "<green>Selected</green>")
    or menuText("templates.navigation.click_to_view_lore", "<gray>Click to view</gray>") }

  items[#items + 1] = {
    slot = catalog.quickBuyButtonSlot, material = catalog.quickBuyButtonMaterial, amount = catalog.quickBuyButtonAmount,
    name = qbName, lore = qbLore, actions = { "MODULE;bed_wars;shop:category:quick_buy" },
  }

  for _, cat in ipairs(catalog.categories) do
    local selected = cat.id == activeCategory
    local name = (selected and menuText("templates.category.tab_selected", "<yellow>{category}</yellow>")
      or menuText("templates.category.tab", "<gray>{category}</gray>")):gsub("{category}", cat.name)
    local lore = {}
    for _, line in ipairs(cat.lore) do lore[#lore + 1] = line end
    lore[#lore + 1] = selected and menuText("templates.navigation.selected_lore", "<green>Selected</green>")
      or menuText("templates.navigation.click_to_view_lore", "<gray>Click to view</gray>")
    items[#items + 1] = {
      slot = cat.slot, material = cat.icon, amount = cat.amount, name = name, lore = lore,
      actions = { "MODULE;bed_wars;shop:category:" .. cat.id },
    }
  end

  for _, slot in ipairs(catalog.separatorSlots) do
    local isSelectedSep = false
    if activeCategory then
      local activeCat = findCategory(catalog, activeCategory)
      if activeCat and slot == activeCat.slot + 9 then isSelectedSep = true end
    elseif slot == catalog.quickBuyButtonSlot + 9 then
      isSelectedSep = true
    end
    items[#items + 1] = {
      slot = slot, material = isSelectedSep and catalog.separatorSelected or catalog.separatorRegular, amount = 1,
      name = " ", lore = {}, actions = {},
    }
  end

  return items
end

function M.openQuickBuy(session, handle)
  local catalog = loadShop()
  local items = buildNavigation(session, handle, nil, catalog)
  local occupied = {}
  for _, entry in ipairs(catalog.quickBuyDefaults) do
    occupied[entry.slot] = entry
  end

  for _, slot in ipairs(catalog.quickBuySlots) do
    local entry = occupied[slot]
    local placed = false
    if entry then
      local cat = findCategory(catalog, entry.categoryId)
      if cat then
        local content = findContent(cat, entry.contentId)
        if content then
          local cache = getCache(session, handle)
          items[#items + 1] = buildContentDefinition(session, handle, cache, content)
          items[#items].slot = slot
          placed = true
        end
      end
    end
    if not placed then
      local emptyLore = ba.config.getStringListFrom("shop.yml", "templates.quick_buy.empty.lore")
      if #emptyLore == 0 then
        emptyLore = { "<red>This is a Quick Buy Slot!</red>", "<gray>Sneak Click any item in</gray>", "<gray>the shop to add it here.</gray>" }
      end
      items[#items + 1] = {
        slot = slot, material = catalog.quickBuyEmpty, amount = 1,
        name = menuText("templates.quick_buy.empty.name", " "), lore = emptyLore, actions = {},
      }
    end
  end

  local title = (ba.config.getStringFrom("shop.yml", "menu_name", "<dark_gray>Item Shop"))
    :gsub("{view}", menuText("templates.quick_buy.view", "Quick Buy"))
  session.menu.open(handle, title, catalog.menuSize, items, {})
  session.state.playersInShop[handle] = true
end

function M.openCategory(session, handle, categoryId)
  local catalog = loadShop()
  local category = findCategory(catalog, categoryId)
  if not category then return end

  local items = buildNavigation(session, handle, categoryId, catalog)
  local cache = getCache(session, handle)
  for _, content in ipairs(category.content) do
    items[#items + 1] = buildContentDefinition(session, handle, cache, content)
  end

  local title = (ba.config.getStringFrom("shop.yml", "menu_name", "<dark_gray>Item Shop")):gsub("{view}", category.name)
  session.menu.open(handle, title, catalog.menuSize, items, {})
  session.state.playersInShop[handle] = true
end

function M.openShop(session, handle)
  local catalog = loadShop()
  if #catalog.categories == 0 then
    local msg = session.config.translation(handle, "messages.shop.not_configured") or "<red>Shop is not configured.</red>"
    session.messages.sendRaw(handle, msg)
    return
  end
  session.state.shopSelectedCategory[handle] = nil
  M.openQuickBuy(session, handle)
end

function M.handleAction(session, handle, payload)
  if payload == "shop:back" then
    session.state.shopSelectedCategory[handle] = nil
    M.openShop(session, handle)
    return true
  end

  local categoryId = payload:match("^shop:category:(.+)$")
  if categoryId then
    if categoryId == "quick_buy" then
      session.state.shopSelectedCategory[handle] = nil
      M.openQuickBuy(session, handle)
    else
      session.state.shopSelectedCategory[handle] = categoryId
      M.openCategory(session, handle, categoryId)
    end
    return true
  end

  local contentId = payload:match("^shop:buy:(.+)$")
  if contentId then
    local catalog = loadShop()
    local currentCategory = session.state.shopSelectedCategory[handle]
    local cat, content = nil, nil
    if currentCategory then
      cat = findCategory(catalog, currentCategory)
      if cat then content = findContent(cat, contentId) end
    else
      for _, c in ipairs(catalog.categories) do
        content = findContent(c, contentId)
        if content then cat = c break end
      end
    end
    if content and cat then
      purchaseContent(session, handle, cat, content)
      if currentCategory then
        M.openCategory(session, handle, currentCategory)
      else
        M.openQuickBuy(session, handle)
      end
      return true
    end
  end

  return false
end

function M.isPlayerInShop(session, handle)
  return session.state.playersInShop[handle] == true
end

function M.onPlayerCloseShop(session, handle)
  session.state.playersInShop[handle] = nil
end

-- Quick Buy customization isn't ported (see file doc); swallows every shift-click while in the
-- shop instead, so it doesn't fall through as a normal inventory move.
function M.handleShopShiftClick(session, handle, slot)
  return M.isPlayerInShop(session, handle)
end

function M.restoreOnRespawn(session, handle)
  local catalog = loadShop()
  local cache = getCache(session, handle)
  for _, cat in ipairs(catalog.categories) do
    for _, content in ipairs(cat.content) do
      if content.permanent or content.downgradable then
        local tierIndex = cache.tiers[content.id]
        if tierIndex and tierIndex >= 0 then
          if content.downgradable and tierIndex > 0 then
            tierIndex = tierIndex - 1
            cache.tiers[content.id] = tierIndex
          end
          if tierIndex >= 0 then
            local tier = content.tiers[tierIndex + 1]
            for _, bi in ipairs(tier.buyItems) do
              giveBuyItem(session, handle, bi, content)
            end
          end
        end
      end
    end
  end
end

function M.clearArena(session)
  session.state.shopSelectedCategory = {}
  session.state.shopCache = {}
  session.state.playersInShop = {}
end

return M

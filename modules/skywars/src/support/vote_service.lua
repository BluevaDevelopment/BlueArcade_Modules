--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy SkyWarsVoteService.java + VoteState.java. All 5 menus are built directly in Lua using
-- "MODULE;skywars;..." actions, not the legacy YAML's "OPEN;<menuId>" (same decision as capture_the_wool).
local VoteState = require("support.vote_state")

local M = {}

local WAITING_ITEM_ID = "skywars_vote_settings"
local VOTE_PERMISSION_BASE = "bluearcade.skywars.votes"

local CATEGORY_OPTION_SET = {
  chests = { basic = true, normal = true, overpowered = true },
  hearts = { ["10"] = true, ["20"] = true, ["30"] = true },
  time = { day = true, night = true, sunset = true, sunrise = true },
  weather = { sunny = true, rainy = true },
}

-- Slot/material layout matches the legacy menu YAMLs exactly.
local MAIN_MENU_BUTTONS = {
  { category = "chests", slot = 10, material = "CHEST", nameKey = "votes.menu.main.chests_name" },
  { category = "hearts", slot = 12, material = "APPLE", nameKey = "votes.menu.main.hearts_name" },
  { category = "time", slot = 14, material = "CLOCK", nameKey = "votes.menu.main.time_name" },
  { category = "weather", slot = 16, material = "WATER_BUCKET", nameKey = "votes.menu.main.weather_name" },
}

local CATEGORY_MENU_ITEMS = {
  chests = {
    { option = "basic", slot = 10, material = "CHEST" },
    { option = "normal", slot = 13, material = "TRAPPED_CHEST" },
    { option = "overpowered", slot = 16, material = "ENDER_CHEST" },
  },
  hearts = {
    { option = "10", slot = 10, material = "REDSTONE" },
    { option = "20", slot = 13, material = "GOLDEN_APPLE" },
    { option = "30", slot = 16, material = "ENCHANTED_GOLDEN_APPLE" },
  },
  time = {
    { option = "day", slot = 10, material = "SUNFLOWER" },
    { option = "sunset", slot = 12, material = "ORANGE_DYE" },
    { option = "night", slot = 14, material = "END_ROD" },
    { option = "sunrise", slot = 16, material = "YELLOW_DYE" },
  },
  weather = {
    { option = "sunny", slot = 11, material = "SUNFLOWER" },
    { option = "rainy", slot = 15, material = "WATER_BUCKET" },
  },
}

-- Module-level, shared across every arena this module runs.
local waitingVoteStates = {}
local voteCooldowns = {}

local function translate(session, handle, key)
  if session then
    return session.config.translation(handle, key)
  end
  return ba.config.translation(nil, key)
end

local function isOptionValid(category, option)
  local set = CATEGORY_OPTION_SET[category]
  return set ~= nil and set[option] == true
end

local function normalizeOption(value, category, fallback)
  local normalized = value and value:lower() or fallback
  if isOptionValid(category, normalized) then
    return normalized
  end
  return fallback
end

local function getCategoryLabel(session, handle, category)
  return translate(session, handle, "votes.labels.categories." .. category) or category
end

local function getOptionLabel(session, handle, category, option)
  return translate(session, handle, "votes.labels.options." .. category .. "." .. option) or option
end

local function getOptionLore(session, handle, category, option)
  return translate(session, handle, "votes.labels.option_lore." .. category .. "." .. option) or ""
end

-- "overpowered" maps to the "op" permission node (bluearcade.skywars.votes.chests.op), matching legacy.
local function mapPermissionOption(category, option)
  if category == "chests" and option == "overpowered" then
    return "op"
  end
  return option
end

local function hasVotePermission(session, handle, category, option)
  local optionKey = mapPermissionOption(category, option)
  local wildcard = VOTE_PERMISSION_BASE .. ".*"
  local categoryWildcard = VOTE_PERMISSION_BASE .. "." .. category .. ".*"
  local exact = VOTE_PERMISSION_BASE .. "." .. category .. "." .. optionKey
  local check = function(permission)
    if session then
      return session.player.hasPermission(handle, permission)
    end
    return ba.playerUtil.hasPermission(handle, permission)
  end
  if check(wildcard) or check(categoryWildcard) or check(exact) then
    return true
  end
  if category == "chests" then
    return check(VOTE_PERMISSION_BASE .. ".chest.*") or check(VOTE_PERMISSION_BASE .. ".chest." .. optionKey)
  end
  return false
end

local function getVoteCooldownSeconds()
  return ba.config.getInt("votes.cooldown_seconds", 5)
end

local function getRemainingVoteCooldownSeconds(handle)
  local cooldownSeconds = getVoteCooldownSeconds()
  if cooldownSeconds <= 0 then
    return 0
  end
  local lastVote = voteCooldowns[handle]
  if not lastVote then
    return 0
  end
  local remaining = cooldownSeconds - (os.clock() - lastVote)
  if remaining <= 0 then
    return 0
  end
  return math.ceil(remaining)
end

local function getWaitingVoteState(arenaId)
  local existing = waitingVoteStates[arenaId]
  if existing then
    return existing
  end
  local created = M.createVoteState()
  waitingVoteStates[arenaId] = created
  return created
end

local function cleanStaleVotesForArena(state, arenaId)
  for _, playerId in ipairs(VoteState.getVoterIds(state)) do
    local currentArena = ba.playerUtil.getArena(playerId)
    if currentArena == nil or currentArena ~= arenaId then
      VoteState.clearPlayerVotes(state, playerId)
    end
  end
end

function M.clearActiveVote(session, playerId)
  local voteState = session.state.voteState
  if voteState then
    VoteState.clearPlayerVotes(voteState, playerId)
  end
end

function M.clearWaitingVote(arenaId, playerId)
  voteCooldowns[playerId] = nil
  local state = waitingVoteStates[arenaId]
  if not state then
    return
  end
  VoteState.clearPlayerVotes(state, playerId)
  if #VoteState.getVoterIds(state) == 0 then
    waitingVoteStates[arenaId] = nil
  end
end

function M.createVoteState()
  local defaults = {
    chests = normalizeOption(ba.config.getString("votes.defaults.chests"), "chests", "normal"),
    hearts = normalizeOption(ba.config.getString("votes.defaults.hearts"), "hearts", "10"),
    time = normalizeOption(ba.config.getString("votes.defaults.time"), "time", "day"),
    weather = normalizeOption(ba.config.getString("votes.defaults.weather"), "weather", "sunny"),
  }
  return VoteState.new(defaults)
end

function M.applyPendingVotes(session)
  local voteState = session.state.voteState
  if not voteState then
    return
  end

  local waiting = getWaitingVoteState(session.arenaId)
  cleanStaleVotesForArena(waiting, session.arenaId)

  for _, handle in ipairs(session.players()) do
    for category in pairs(CATEGORY_OPTION_SET) do
      local option = VoteState.getPlayerVote(waiting, handle, category)
      if option then
        VoteState.castVote(voteState, handle, category, option)
      end
    end
    voteCooldowns[handle] = nil
  end
  waitingVoteStates[session.arenaId] = nil
end

local function resolveHearts(option)
  if option == "20" then return 20 end
  if option == "30" then return 30 end
  return 10
end

local function timeTicksFor(option)
  if option == "night" then return 13000 end
  if option == "sunset" then return 12000 end
  if option == "sunrise" then return 23000 end
  return 1000
end

function M.applyVotes(session)
  local voteState = session.state.voteState
  if not voteState then
    return
  end

  local chestTier = VoteState.resolveWinner(voteState, "chests")
  local hearts = VoteState.resolveWinner(voteState, "hearts")
  local time = VoteState.resolveWinner(voteState, "time")
  local weather = VoteState.resolveWinner(voteState, "weather")

  session.state.selectedChestTier = chestTier
  session.state.selectedHearts = resolveHearts(hearts)
  session.state.selectedTime = time
  session.state.selectedWeather = weather

  local maxHealth = math.max(2.0, session.state.selectedHearts * 2.0)
  for _, handle in ipairs(session.players()) do
    session.player.setMaxHealth(handle, maxHealth)
    session.player.setHealth(handle, math.min(maxHealth, session.player.maxHealth(handle)))
  end

  session.world.setTime(timeTicksFor(time))

  local rainy = weather == "rainy"
  session.world.setStorm(rainy)
  session.world.setThundering(false)
end

local function broadcastResultForCategory(session, voteState, category, messageKey)
  local option = VoteState.resolveWinner(voteState, category)
  local sourceKey = VoteState.hasVotes(voteState, category)
    and "votes.messages.selected.sources.popular"
    or "votes.messages.selected.sources.default"
  local source = session.config.translation(nil, sourceKey)
  local message = session.config.translation(nil, messageKey)
  if not message or message == "" then
    return
  end
  message = message:gsub("{option}", getOptionLabel(session, nil, category, option):upper()):gsub("{source}", source or "")
  for _, handle in ipairs(session.players()) do
    session.messages.sendRaw(handle, message)
  end
end

function M.broadcastVoteResults(session)
  local voteState = session.state.voteState
  if not voteState then
    return
  end
  broadcastResultForCategory(session, voteState, "chests", "votes.messages.selected.chests")
  broadcastResultForCategory(session, voteState, "hearts", "votes.messages.selected.hearts")
  broadcastResultForCategory(session, voteState, "time", "votes.messages.selected.time")
  broadcastResultForCategory(session, voteState, "weather", "votes.messages.selected.weather")
end

local function buildMainMenuItems(session, handle, voteState)
  local items = {}

  items[#items + 1] = {
    slot = 4,
    material = "BOOK",
    amount = 1,
    name = translate(session, handle, "votes.menu.main.info_name") or "",
    lore = session and session.config.translationList(handle, "votes.menu.main.info_lore") or ba.config.translationList(nil, "votes.menu.main.info_lore"),
    actions = {},
  }

  for _, button in ipairs(MAIN_MENU_BUTTONS) do
    local yourVote = translate(session, handle, "votes.messages.your_vote")
    local playerVote = VoteState.getPlayerVote(voteState, handle, button.category)
    local voteLine = yourVote and yourVote:gsub("{option}", playerVote and getOptionLabel(session, handle, button.category, playerVote) or "-") or ""

    items[#items + 1] = {
      slot = button.slot,
      material = button.material,
      amount = 1,
      name = translate(session, handle, button.nameKey) or button.category,
      lore = { voteLine, translate(session, handle, "votes.messages.click_to_vote") or "" },
      actions = { "MODULE;skywars;menu " .. button.category },
    }
  end

  items[#items + 1] = {
    slot = 22,
    material = "BARRIER",
    amount = 1,
    name = translate(session, handle, "votes.menu.main.close_name") or "Close",
    lore = { translate(session, handle, "votes.menu.main.close_lore") or "" },
    actions = { "CLOSE" },
  }

  return items
end

local function buildCategoryMenuItems(session, handle, voteState, category)
  local items = {}
  local votesCountTemplate = translate(session, handle, "votes.messages.votes_count") or ""
  local clickToVote = translate(session, handle, "votes.messages.click_to_vote") or ""

  for _, entry in ipairs(CATEGORY_MENU_ITEMS[category]) do
    local votes = VoteState.getVotes(voteState, category, entry.option)
    local votesLine = votesCountTemplate:gsub("{count}", tostring(votes))
    local optionLore = getOptionLore(session, handle, category, entry.option)

    items[#items + 1] = {
      slot = entry.slot,
      material = entry.material,
      amount = 1,
      name = getOptionLabel(session, handle, category, entry.option),
      lore = { votesLine, optionLore, clickToVote },
      actions = { "MODULE;skywars;vote " .. category .. " " .. entry.option },
    }
  end

  items[#items + 1] = {
    slot = 22,
    material = "ARROW",
    amount = 1,
    name = translate(session, handle, "votes.menu.back_name") or "Back",
    lore = { translate(session, handle, "votes.menu.back_lore") or "" },
    actions = { "MODULE;skywars;menu main" },
  }

  return items
end

local function openMenu(session, handle, voteState, menuId)
  local title
  local items
  if menuId == "chests" or menuId == "hearts" or menuId == "time" or menuId == "weather" then
    title = translate(session, handle, "votes.menu." .. menuId .. ".title") or menuId
    items = buildCategoryMenuItems(session, handle, voteState, menuId)
  else
    title = translate(session, handle, "votes.menu.main.title") or "SkyWars - Votes"
    items = buildMainMenuItems(session, handle, voteState)
  end

  if session then
    return session.menu.open(handle, title, 27, items, {})
  end
  return ba.menu.open(handle, title, 27, items, {})
end

local function mapMenuId(id)
  if id == "chests" or id == "hearts" or id == "time" or id == "weather" then
    return id
  end
  return "main"
end

function M.handleVoteCommand(session, handle, args)
  local voteState = session.state.voteState

  if #args == 0 then
    openMenu(session, handle, voteState, "main")
    return true
  end

  local action = args[1]:lower()
  if action == "menu" then
    openMenu(session, handle, voteState, mapMenuId(args[2]))
    return true
  end

  if action == "vote" then
    if #args < 3 then
      session.messages.sendRaw(handle, session.config.translation(handle, "votes.messages.invalid"))
      return true
    end

    local category = args[2]:lower()
    local option = args[3]:lower()
    if not isOptionValid(category, option) then
      session.messages.sendRaw(handle, session.config.translation(handle, "votes.messages.invalid"))
      return true
    end
    if not hasVotePermission(session, handle, category, option) then
      local message = session.config.translation(handle, "votes.messages.no_permission")
      if message then
        session.messages.sendRaw(handle, message:gsub("{option}", getOptionLabel(session, handle, category, option)))
      end
      return true
    end
    if not voteState then
      return true
    end

    local cooldownRemaining = getRemainingVoteCooldownSeconds(handle)
    if cooldownRemaining > 0 then
      local message = session.config.translation(handle, "votes.messages.cooldown")
      if message then
        session.messages.sendRaw(handle, message:gsub("{time}", tostring(cooldownRemaining)))
      end
      return true
    end

    local previousVote = VoteState.getPlayerVote(voteState, handle, category)
    VoteState.castVote(voteState, handle, category, option)
    voteCooldowns[handle] = os.clock()

    if previousVote ~= option then
      local message = session.config.translation(handle, "votes.messages.broadcast")
      if message and message ~= "" then
        local voteCount = VoteState.getVotes(voteState, category, option)
        message = message:gsub("{player}", session.player.name(handle))
          :gsub("{category}", getCategoryLabel(session, handle, category))
          :gsub("{option}", getOptionLabel(session, handle, category, option))
          :gsub("{votes}", tostring(voteCount))
        for _, p in ipairs(session.players()) do
          session.messages.sendRaw(p, message)
        end
      end
    end
    return true
  end

  openMenu(session, handle, voteState, "main")
  return true
end

function M.handleVoteCommandWithoutContext(handle, args)
  local arenaId = ba.playerUtil.getArena(handle)
  if not arenaId then
    return true
  end

  local waiting = getWaitingVoteState(arenaId)
  cleanStaleVotesForArena(waiting, arenaId)

  args = args or {}
  if #args == 0 then
    openMenu(nil, handle, waiting, "main")
    return true
  end

  local action = args[1]:lower()
  if action == "menu" then
    openMenu(nil, handle, waiting, mapMenuId(args[2]))
    return true
  end

  if action == "vote" then
    if #args < 3 then
      return true
    end

    local category = args[2]:lower()
    local option = args[3]:lower()
    if not isOptionValid(category, option) then
      return true
    end
    if not hasVotePermission(nil, handle, category, option) then
      return true
    end

    local cooldownRemaining = getRemainingVoteCooldownSeconds(handle)
    if cooldownRemaining > 0 then
      local message = ba.config.translation(nil, "votes.messages.cooldown")
      if message and message ~= "" then
        ba.messages.sendRaw(handle, message:gsub("{time}", tostring(cooldownRemaining)))
      end
      openMenu(nil, handle, waiting, "main")
      return true
    end

    -- Unlike an in-session vote, a waiting-room vote doesn't broadcast to the rest of the lobby -
    -- same documented, deliberate gap as lucky_pillars'/capture_the_wool's own vote_service.lua.
    VoteState.castVote(waiting, handle, category, option)
    voteCooldowns[handle] = os.clock()
    openMenu(nil, handle, waiting, "main")
    return true
  end

  return false
end

function M.handleVoteAction(handle, args)
  local session = ba.session.forPlayer(handle)
  if not session then
    return M.handleVoteCommandWithoutContext(handle, args)
  end

  local phase = session.phase()
  if phase == "PLAYING" or phase == "ENDING" or phase == "FINISHED" then
    session.messages.sendRaw(handle, session.config.translation(handle, "votes.messages.not_available"))
    return true
  end

  return M.handleVoteCommand(session, handle, args)
end

function M.registerWaitingItem()
  if not ba.config.getBoolean("waiting_items.vote_settings.enabled", true) then
    return
  end
  local material = ba.config.getString("waiting_items.vote_settings.material") or "NAME_TAG"
  local slot = ba.config.getInt("waiting_items.vote_settings.slot", 1)
  local displayName = ba.config.getString("waiting_items.vote_settings.display_name") or ""
  local lore = ba.config.getStringList("waiting_items.vote_settings.lore")
  ba.items.registerWaitingItem(WAITING_ITEM_ID, material, slot, displayName, lore)
end

function M.registerClickHandler()
  ba.items.onClick(WAITING_ITEM_ID, function(handle)
    return M.handleVoteAction(handle, { "menu", "main" })
  end)
end

return M

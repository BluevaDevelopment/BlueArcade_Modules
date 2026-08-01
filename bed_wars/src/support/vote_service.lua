-- Mirrors legacy BedWarsVoteService.java + VoteState.java + BedWarsVoteMenuRepository.java's own
-- menu construction. Menu item names/lore are hardcoded literal MiniMessage strings taken directly
-- from the legacy menus/java/bed_wars_vote_*.yml files rather than looked up via
-- `session.config.translation` keys - unlike most of this module's other UI, the legacy vote menus
-- never went through the translation system at all (no matching `votes.menu.*` keys exist in
-- language/en.yml/es.yml either), so hardcoding here is a faithful port, not a shortcut.
-- BedWarsMenuAPI.java (the admin-tooling `openMenuById` wrapper registered under a second module id
-- "bed") isn't ported - no player-facing effect, same documented gap as every other converted
-- module's analogous `*MenuAPI` skip. "OPEN;<menuId>" navigation is replaced with
-- "MODULE;bed_wars;menu <id>" throughout, for the same reason capture_the_wool's own vote menu
-- does: a Lua-built session.menu.open/ba.menu.open inventory is never registered under a Core menu
-- id, so "OPEN;" can't reach it.
local VoteState = require("support.vote_state")

local M = {}

local WAITING_ITEM_ID = "bed_wars_vote_settings"
local VOTE_PERMISSION_BASE = "bluearcade.bedwars.votes"

local CATEGORY_OPTION_SET = {
  hearts = { ["10"] = true, ["20"] = true, ["30"] = true },
  time = { day = true, night = true, sunset = true, sunrise = true },
  weather = { sunny = true, rainy = true },
}
local CATEGORIES = { "hearts", "time", "weather" }

-- Slot/material/text layout matches menus/java/bed_wars_vote_*.yml exactly.
local MAIN_MENU_BUTTONS = {
  { category = "hearts", slot = 11, material = "APPLE", name = "<red>Hearts</red>", placeholderLoreLine = "<gray>Your vote:</gray> <white>{value}</white>" },
  { category = "time", slot = 13, material = "CLOCK", name = "<yellow>Time of day</yellow>", placeholderLoreLine = "<gray>Your vote:</gray> <white>{value}</white>" },
  { category = "weather", slot = 15, material = "WATER_BUCKET", name = "<blue>Weather</blue>", placeholderLoreLine = "<gray>Your vote:</gray> <white>{value}</white>" },
}

local CATEGORY_MENU_ITEMS = {
  hearts = {
    { option = "10", slot = 10, material = "REDSTONE", name = "<white>10 hearts</white>", flavor = "<gray>Classic Bed Wars health.</gray>" },
    { option = "20", slot = 13, material = "GOLDEN_APPLE", name = "<yellow>20 hearts</yellow>", flavor = "<gray>Longer fights and more clutch plays.</gray>" },
    { option = "30", slot = 16, material = "ENCHANTED_GOLDEN_APPLE", name = "<light_purple>30 hearts</light_purple>", flavor = "<gray>Extra tanky battles.</gray>" },
  },
  time = {
    { option = "day", slot = 10, material = "SUNFLOWER", name = "<yellow>Day</yellow>", flavor = "<gray>Clear daylight visibility.</gray>" },
    { option = "sunset", slot = 12, material = "ORANGE_DYE", name = "<gold>Sunset</gold>", flavor = "<gray>Warm evening lighting.</gray>" },
    { option = "night", slot = 14, material = "END_ROD", name = "<blue>Night</blue>", flavor = "<gray>Dark, tense battles.</gray>" },
    { option = "sunrise", slot = 16, material = "YELLOW_DYE", name = "<yellow>Sunrise</yellow>", flavor = "<gray>Early morning glow.</gray>" },
  },
  weather = {
    { option = "sunny", slot = 11, material = "SUNFLOWER", name = "<yellow>Sunny</yellow>", flavor = "<gray>Clear skies.</gray>" },
    { option = "rainy", slot = 15, material = "WATER_BUCKET", name = "<blue>Rainy</blue>", flavor = "<gray>Stormy atmosphere.</gray>" },
  },
}

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

local function hasVotePermission(session, handle, category, option)
  local wildcard = VOTE_PERMISSION_BASE .. ".*"
  local categoryWildcard = VOTE_PERMISSION_BASE .. "." .. category .. ".*"
  local exact = VOTE_PERMISSION_BASE .. "." .. category .. "." .. option
  if session then
    return session.player.hasPermission(handle, wildcard)
      or session.player.hasPermission(handle, categoryWildcard)
      or session.player.hasPermission(handle, exact)
  end
  return ba.playerUtil.hasPermission(handle, wildcard)
    or ba.playerUtil.hasPermission(handle, categoryWildcard)
    or ba.playerUtil.hasPermission(handle, exact)
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
    hearts = normalizeOption(ba.config.getString("votes.defaults.hearts"), "hearts", "10"),
    time = normalizeOption(ba.config.getString("votes.defaults.time"), "time", "day"),
    weather = normalizeOption(ba.config.getString("votes.defaults.weather"), "weather", "sunny"),
  }
  return VoteState.new(defaults)
end

function M.applyPendingVotes(session)
  local voteState = session.state.voteState
  if not voteState then return end

  local waiting = getWaitingVoteState(session.arenaId)
  cleanStaleVotesForArena(waiting, session.arenaId)

  for _, handle in ipairs(session.players()) do
    for _, category in ipairs(CATEGORIES) do
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
  if not voteState then return end

  local hearts = VoteState.resolveWinner(voteState, "hearts")
  local time = VoteState.resolveWinner(voteState, "time")
  local weather = VoteState.resolveWinner(voteState, "weather")

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
  if not message or message == "" then return end
  message = message:gsub("{option}", getOptionLabel(session, nil, category, option)):gsub("{source}", source or "")
  for _, handle in ipairs(session.players()) do
    session.messages.sendRaw(handle, message)
  end
end

function M.broadcastVoteResults(session)
  local voteState = session.state.voteState
  if not voteState then return end
  broadcastResultForCategory(session, voteState, "hearts", "votes.messages.selected.hearts")
  broadcastResultForCategory(session, voteState, "time", "votes.messages.selected.time")
  broadcastResultForCategory(session, voteState, "weather", "votes.messages.selected.weather")
end

local function buildMainMenuItems(session, handle, voteState)
  local items = {}

  items[#items + 1] = {
    slot = 4, material = "BOOK", amount = 1,
    name = "<yellow>Match settings</yellow>",
    lore = { "<gray>Vote for the match setup before it starts.</gray>", "<gray>Your votes are shared with everyone.</gray>" },
    actions = {},
  }

  for _, button in ipairs(MAIN_MENU_BUTTONS) do
    local playerVote = VoteState.getPlayerVote(voteState, handle, button.category)
    local valueLine = button.placeholderLoreLine:gsub("{value}", playerVote and getOptionLabel(session, handle, button.category, playerVote) or "-")
    items[#items + 1] = {
      slot = button.slot, material = button.material, amount = 1,
      name = button.name,
      lore = { valueLine, "<green>Click to vote</green>" },
      actions = { "MODULE;bed_wars;menu " .. button.category },
    }
  end

  items[#items + 1] = {
    slot = 22, material = "BARRIER", amount = 1,
    name = "<red>Close</red>",
    lore = { "<gray>Return to the lobby.</gray>" },
    actions = { "CLOSE" },
  }

  return items
end

local function buildCategoryMenuItems(session, handle, voteState, category)
  local items = {}
  for _, entry in ipairs(CATEGORY_MENU_ITEMS[category]) do
    local votes = VoteState.getVotes(voteState, category, entry.option)
    items[#items + 1] = {
      slot = entry.slot, material = entry.material, amount = 1,
      name = entry.name,
      lore = { "<gray>Votes:</gray> <white>" .. tostring(votes) .. "</white>", entry.flavor, "<green>Click to vote</green>" },
      actions = { "MODULE;bed_wars;vote " .. category .. " " .. entry.option },
    }
  end

  items[#items + 1] = {
    slot = 22, material = "ARROW", amount = 1,
    name = "<gray>Back</gray>",
    lore = { "<gray>Return to settings.</gray>" },
    actions = { "MODULE;bed_wars;menu main" },
  }

  return items
end

local function openMenu(session, handle, voteState, menuId)
  local title, items
  if menuId == "hearts" then
    title = "<red>Vote hearts</red>"
    items = buildCategoryMenuItems(session, handle, voteState, "hearts")
  elseif menuId == "time" then
    title = "<yellow>Vote time</yellow>"
    items = buildCategoryMenuItems(session, handle, voteState, "time")
  elseif menuId == "weather" then
    title = "<blue>Vote weather</blue>"
    items = buildCategoryMenuItems(session, handle, voteState, "weather")
  else
    title = "<aqua>Bed Wars vote settings</aqua>"
    items = buildMainMenuItems(session, handle, voteState)
  end

  if session then
    return session.menu.open(handle, title, 27, items, {})
  end
  return ba.menu.open(handle, title, 27, items, {})
end

local function mapMenuId(id)
  if id == "hearts" or id == "time" or id == "weather" then
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
    if not voteState then return true end

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
  if not arenaId then return true end

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
    if #args < 3 then return true end

    local category = args[2]:lower()
    local option = args[3]:lower()
    if not isOptionValid(category, option) then return true end
    if not hasVotePermission(nil, handle, category, option) then return true end

    local cooldownRemaining = getRemainingVoteCooldownSeconds(handle)
    if cooldownRemaining > 0 then
      openMenu(nil, handle, waiting, mapMenuId(category))
      return true
    end

    -- A waiting-room vote doesn't broadcast to the rest of the lobby - same documented gap as
    -- capture_the_wool/lucky_pillars' own vote_service.lua (no "list every other player in this
    -- waiting arena" binding exists yet). The vote itself, the cooldown, and the menu still work.
    VoteState.castVote(waiting, handle, category, option)
    voteCooldowns[handle] = os.clock()
    openMenu(nil, handle, waiting, mapMenuId(category))
    return true
  end

  return false
end

-- The single entry point both the lobby waiting-item click and the menu-action handler dispatch
-- through - mirrors legacy BedWarsGame.handleVoteCommand's own context-or-not routing.
function M.handleVoteAction(handle, payload)
  local args = {}
  for word in payload:gmatch("%S+") do
    args[#args + 1] = word
  end

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
    return M.handleVoteAction(handle, "menu main")
  end)
end

return M

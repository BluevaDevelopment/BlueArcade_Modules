-- Mirrors legacy BuildBattleVoteService.java + VoteState.java's own module-level menu-item
-- construction that legacy sourced from BuildBattleVoteMenuRepository.java (a live YAML->
-- MenuDefinition build fed by the `themes` config list) - here the menu is built directly in Lua
-- from that same `themes` list, one button per theme plus a "Random" button, using
-- "MODULE;build_battle;vote theme <id>" actions. BuildBattleVoteMenuRepository.java/
-- BuildBattleModuleMenuAPI.java/support/vote/BuildBattleMenuAPI.java (all `OPEN;`-based) aren't
-- ported - same reasoning as every prior module's own menu-repository skip.
local VoteState = require("support.vote_state")

local M = {}

local WAITING_ITEM_ID = "build_battle_vote_theme"
local VOTE_PERMISSION_BASE = "bluearcade.build_battle.votes"
local CLOSE_SLOT = 31

-- Module-level, shared across every arena this module runs.
local waitingVoteStates = {}
local voteCooldowns = {}

local function toThemeId(theme)
  return theme:lower():gsub("%s+", "_")
end

local function getThemes()
  local themes = ba.config.getStringList("themes")
  if #themes == 0 then
    themes = { "House" }
  end
  return themes
end

local function getValidThemeIds()
  local ids = { random = true }
  for _, theme in ipairs(getThemes()) do
    ids[toThemeId(theme)] = true
  end
  return ids
end

local function isThemeValid(theme)
  return theme ~= nil and getValidThemeIds()[theme] == true
end

local function getThemeLabel(theme)
  if not theme then
    return ""
  end
  if theme:lower() == "random" then
    return "Random"
  end
  for _, entry in ipairs(getThemes()) do
    if toThemeId(entry) == theme:lower() then
      return entry
    end
  end
  return theme
end

local function translate(session, handle, key)
  if session then
    return session.config.translation(handle, key)
  end
  return ba.config.translation(nil, key)
end

local function hasThemePermission(session, handle, theme)
  local permission = VOTE_PERMISSION_BASE .. "." .. theme:lower()
  local wildcard = VOTE_PERMISSION_BASE .. ".*"
  if session then
    return session.player.hasPermission(handle, permission) or session.player.hasPermission(handle, wildcard)
  end
  return ba.playerUtil.hasPermission(handle, permission) or ba.playerUtil.hasPermission(handle, wildcard)
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
  local raw = ba.config.getString("votes.defaults.theme")
  local defaultTheme = "random"
  if raw and raw ~= "" and getValidThemeIds()[raw:lower()] then
    defaultTheme = raw:lower()
  end
  return VoteState.new(defaultTheme)
end

function M.applyPendingVotes(session)
  local voteState = session.state.voteState
  if not voteState then
    return
  end

  local waiting = getWaitingVoteState(session.arenaId)
  cleanStaleVotesForArena(waiting, session.arenaId)

  for _, handle in ipairs(session.players()) do
    local theme = VoteState.getPlayerVote(waiting, handle)
    if theme then
      VoteState.castVote(voteState, handle, theme)
    end
    voteCooldowns[handle] = nil
  end
  waitingVoteStates[session.arenaId] = nil
end

-- applyVotes - "random" resolves to a random pick from the `themes` list only now, at apply time,
-- matching legacy BuildBattleVoteService.applyVotes exactly (not at vote-cast time).
function M.applyVotes(session)
  local voteState = session.state.voteState
  if not voteState then
    return
  end

  local theme = VoteState.resolveWinner(voteState)
  if theme and theme:lower() == "random" then
    local themes = getThemes()
    theme = themes[math.random(#themes)]
  else
    theme = getThemeLabel(theme)
  end
  session.state.selectedTheme = theme
end

function M.broadcastVoteResults(session)
  local voteState = session.state.voteState
  if not voteState then
    return
  end

  local winner = VoteState.resolveWinner(voteState)
  local themeLabel = session.state.selectedTheme or getThemeLabel(winner)
  local sourceKey = VoteState.hasVotes(voteState)
      and "votes.messages.selected.sources.popular"
      or "votes.messages.selected.sources.default"
  local source = session.config.translation(nil, sourceKey)

  local message = session.config.translation(nil, "votes.messages.selected.theme")
  if message and message ~= "" then
    message = message:gsub("{theme}", themeLabel):gsub("{source}", source or "")
    for _, handle in ipairs(session.players()) do
      session.messages.sendRaw(handle, message)
    end
  end
end

local function buildMenuItems(session, handle, voteState)
  local items = {}
  local slot = 10
  local entries = { { id = "random", material = "ENDER_EYE" } }
  for _, theme in ipairs(getThemes()) do
    entries[#entries + 1] = { id = toThemeId(theme), material = "PAPER" }
  end

  for _, entry in ipairs(entries) do
    if slot == CLOSE_SLOT then
      slot = slot + 1
    end
    local votes = voteState and VoteState.getVotes(voteState, entry.id) or 0
    local votesLine = translate(session, handle, "votes.messages.votes_count") or ""
    votesLine = votesLine:gsub("{count}", tostring(votes))

    items[#items + 1] = {
      slot = slot,
      material = entry.material,
      amount = 1,
      name = getThemeLabel(entry.id),
      lore = { votesLine, translate(session, handle, "votes.messages.click_to_vote") or "" },
      actions = { "MODULE;build_battle;vote theme " .. entry.id },
    }
    slot = slot + 1
  end

  items[#items + 1] = {
    slot = CLOSE_SLOT,
    material = "BARRIER",
    amount = 1,
    name = translate(session, handle, "votes.messages.close") or "Close",
    lore = { translate(session, handle, "votes.messages.close_lore") or "" },
    actions = { "CLOSE" },
  }

  return items
end

local function openMenu(session, handle, voteState)
  local title = translate(session, handle, "vote_menu.name") or "Build Battle"
  local items = buildMenuItems(session, handle, voteState)
  if session then
    return session.menu.open(handle, title, 36, items, {})
  end
  return ba.menu.open(handle, title, 36, items, {})
end

function M.handleVoteCommand(session, handle, args)
  if #args == 0 then
    openMenu(session, handle, session.state.voteState)
    return true
  end

  local action = args[1]:lower()
  if action == "menu" then
    openMenu(session, handle, session.state.voteState)
    return true
  end

  if action == "vote" then
    if #args < 3 then
      session.messages.sendRaw(handle, session.config.translation(handle, "votes.messages.invalid"))
      return true
    end

    local theme = args[3]:lower()
    if not isThemeValid(theme) then
      session.messages.sendRaw(handle, session.config.translation(handle, "votes.messages.invalid"))
      return true
    end
    if not hasThemePermission(session, handle, theme) then
      local message = session.config.translation(handle, "votes.messages.no_permission")
      if message then
        session.messages.sendRaw(handle, message:gsub("{theme}", getThemeLabel(theme)))
      end
      return true
    end

    local voteState = session.state.voteState
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

    local previousVote = VoteState.getPlayerVote(voteState, handle)
    VoteState.castVote(voteState, handle, theme)
    voteCooldowns[handle] = os.clock()

    if previousVote ~= theme then
      local message = session.config.translation(handle, "votes.messages.broadcast")
      if message and message ~= "" then
        local voteCount = VoteState.getVotes(voteState, theme)
        message = message:gsub("{player}", session.player.name(handle))
          :gsub("{theme}", getThemeLabel(theme))
          :gsub("{votes}", tostring(voteCount))
        for _, p in ipairs(session.players()) do
          session.messages.sendRaw(p, message)
        end
      end
    end
    return true
  end

  openMenu(session, handle, session.state.voteState)
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
    openMenu(nil, handle, waiting)
    return true
  end

  local action = args[1]:lower()
  if action == "menu" then
    openMenu(nil, handle, waiting)
    return true
  end

  if action == "vote" then
    if #args < 3 then
      return true
    end

    local theme = args[3]:lower()
    if not isThemeValid(theme) then
      return true
    end
    if not hasThemePermission(nil, handle, theme) then
      return true
    end

    local cooldownRemaining = getRemainingVoteCooldownSeconds(handle)
    if cooldownRemaining > 0 then
      openMenu(nil, handle, waiting)
      return true
    end

    local previousVote = VoteState.getPlayerVote(waiting, handle)
    VoteState.castVote(waiting, handle, theme)
    voteCooldowns[handle] = os.clock()
    openMenu(nil, handle, waiting)
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
  if not ba.config.getBoolean("waiting_items.vote_theme.enabled", true) then
    return
  end
  local material = ba.config.getString("waiting_items.vote_theme.material") or "PAPER"
  local slot = ba.config.getInt("waiting_items.vote_theme.slot", 1)
  local displayName = ba.config.getString("waiting_items.vote_theme.display_name") or ""
  local lore = ba.config.getStringList("waiting_items.vote_theme.lore")
  ba.items.registerWaitingItem(WAITING_ITEM_ID, material, slot, displayName, lore)
end

function M.registerClickHandler()
  ba.items.onClick(WAITING_ITEM_ID, function(handle)
    return M.handleVoteAction(handle, { "menu", "theme" })
  end)
end

return M

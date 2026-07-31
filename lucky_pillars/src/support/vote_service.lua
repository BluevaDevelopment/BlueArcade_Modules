-- Mirrors legacy LuckyPillarsVoteService.java + VoteState.java's own module-level menu-item
-- construction that legacy sourced from LuckyPillarsVoteMenuRepository.java (a live YAML->
-- MenuDefinition build) - here the menu's slots/materials/text are built directly in Lua from the
-- same modifier list, resolving text through session/module config translations instead. The
-- "close" button and "vote" item actions match the legacy menu YAML exactly (slot numbers,
-- MODULE;lucky_pillars;vote modifier <id> action strings). LuckyPillarsVoteMenuRepository.java/
-- LuckyPillarsMenuAPI.java (a thin openMenuById delegate for the redundant /lucky_pillarsvote
-- slash command, see LuckyPillarsVoteListener.java) aren't ported - the lobby-item-click and
-- menu-action-handler paths already cover the same functionality. cleanStaleVotes() (the no-arg,
-- all-arenas variant) is dead code in the legacy source too (never called anywhere) - only the
-- per-arena cleanStaleVotesForArena is real. The waiting-room "broadcast this vote to everyone
-- else in the lobby" notification (legacy's broadcastToWaitingArena) is a documented, deliberate
-- gap - see docs/BAMODULE_STATUS.md - it needs a "list all online players" binding nothing else
-- has needed yet; the vote itself, the cooldown, and the menu still work correctly.
local VoteState = require("support.vote_state")

local M = {}

local WAITING_ITEM_ID = "lucky_pillars_vote_settings"

local MODIFIERS = {
  { id = "none", material = "BARRIER", slot = 10 },
  { id = "elytra", material = "ELYTRA", slot = 11 },
  { id = "swap", material = "ENDER_PEARL", slot = 12 },
  { id = "speed", material = "CLOCK", slot = 13 },
  { id = "slow_fall", material = "FEATHER", slot = 14 },
  { id = "invisibility", material = "POTION", slot = 15 },
  { id = "double_health", material = "GOLDEN_APPLE", slot = 16 },
  { id = "one_heart", material = "RED_DYE", slot = 19 },
  { id = "unbreakable", material = "OBSIDIAN", slot = 20 },
  { id = "ultra_jump", material = "RABBIT_FOOT", slot = 21 },
  { id = "rising_lava", material = "LAVA_BUCKET", slot = 23 },
}

local MODIFIER_SET = {}
for _, entry in ipairs(MODIFIERS) do
  MODIFIER_SET[entry.id] = true
end

-- Module-level, shared across every arena this module runs - mirrors the legacy service's own
-- instance fields (one LuckyPillarsVoteService per module, not per arena).
local waitingVoteStates = {}
local voteCooldowns = {}

local function isModifierValid(modifier)
  return modifier ~= nil and MODIFIER_SET[modifier] == true
end

local function translate(session, handle, key)
  if session then
    return session.config.translation(handle, key)
  end
  return ba.config.translation(nil, key)
end

local function getModifierLabel(session, handle, modifier)
  if not modifier then
    return ""
  end
  local label = translate(session, handle, "votes.labels.modifiers." .. modifier)
  return label or modifier
end

local function hasModifierPermission(session, handle, modifier)
  local permission = "bluearcade.lucky_pillars.votes." .. modifier
  local wildcard = "bluearcade.lucky_pillars.votes.*"
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

-- clearActiveVote - the in-session half of legacy LuckyPillarsGame.onPlayerQuit (the waiting-room
-- half is M.clearWaitingVote below).
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
  local raw = ba.config.getString("votes.defaults.modifier")
  local defaultModifier = "none"
  if raw and raw ~= "" and MODIFIER_SET[raw:lower()] then
    defaultModifier = raw:lower()
  end
  return VoteState.new(defaultModifier)
end

function M.applyPendingVotes(session)
  local voteState = session.state.voteState
  if not voteState then
    return
  end

  local waiting = getWaitingVoteState(session.arenaId)
  cleanStaleVotesForArena(waiting, session.arenaId)

  for _, handle in ipairs(session.players()) do
    local modifier = VoteState.getPlayerVote(waiting, handle)
    if modifier then
      VoteState.castVote(voteState, handle, modifier)
    end
    voteCooldowns[handle] = nil
  end
  waitingVoteStates[session.arenaId] = nil
end

function M.applyVotes(session)
  local voteState = session.state.voteState
  if not voteState then
    return
  end
  session.state.selectedModifier = VoteState.resolveWinner(voteState)
end

function M.broadcastVoteResults(session)
  local voteState = session.state.voteState
  if not voteState then
    return
  end

  local modifier = VoteState.resolveWinner(voteState)
  local modifierLabel = getModifierLabel(session, nil, modifier)
  local sourceKey = VoteState.hasVotes(voteState)
      and "votes.messages.selected.sources.popular"
      or "votes.messages.selected.sources.default"
  local source = session.config.translation(nil, sourceKey)

  local message = session.config.translation(nil, "votes.messages.selected.modifier")
  if message and message ~= "" then
    message = message:gsub("{modifier}", modifierLabel):gsub("{source}", source or "")
    for _, handle in ipairs(session.players()) do
      session.messages.sendRaw(handle, message)
    end
  end
end

local function buildMenuItems(session, handle, voteState)
  local items = {}
  for _, entry in ipairs(MODIFIERS) do
    local votes = voteState and VoteState.getVotes(voteState, entry.id) or 0
    local votesLine = translate(session, handle, "votes.messages.votes_count") or ""
    votesLine = votesLine:gsub("{count}", tostring(votes))

    items[#items + 1] = {
      slot = entry.slot,
      material = entry.material,
      amount = 1,
      name = getModifierLabel(session, handle, entry.id),
      lore = {
        translate(session, handle, "votes.labels.modifier_lore." .. entry.id) or "",
        votesLine,
        translate(session, handle, "votes.messages.click_to_vote") or "",
      },
      actions = { "MODULE;lucky_pillars;vote modifier " .. entry.id },
    }
  end

  items[#items + 1] = {
    slot = 31,
    material = "BARRIER",
    amount = 1,
    name = translate(session, handle, "votes.messages.close") or "Close",
    lore = { translate(session, handle, "votes.messages.close_lore") or "" },
    actions = { "CLOSE" },
  }

  return items
end

local function openMenu(session, handle, voteState)
  local title = translate(session, handle, "vote_menu_modifiers.title") or "Lucky Pillars - Modifiers"
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

    local modifier = args[3]:lower()
    if not isModifierValid(modifier) then
      session.messages.sendRaw(handle, session.config.translation(handle, "votes.messages.invalid"))
      return true
    end
    if not hasModifierPermission(session, handle, modifier) then
      local message = session.config.translation(handle, "votes.messages.no_permission")
      if message then
        session.messages.sendRaw(handle, message:gsub("{modifier}", getModifierLabel(session, handle, modifier)))
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
    VoteState.castVote(voteState, handle, modifier)
    voteCooldowns[handle] = os.clock()

    if previousVote ~= modifier then
      local message = session.config.translation(handle, "votes.messages.broadcast")
      if message and message ~= "" then
        local voteCount = VoteState.getVotes(voteState, modifier)
        message = message:gsub("{player}", session.player.name(handle))
          :gsub("{modifier}", getModifierLabel(session, handle, modifier))
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

    local modifier = args[3]:lower()
    if not isModifierValid(modifier) then
      return true
    end
    if not hasModifierPermission(nil, handle, modifier) then
      return true
    end

    local cooldownRemaining = getRemainingVoteCooldownSeconds(handle)
    if cooldownRemaining > 0 then
      local message = ba.config.translation(nil, "votes.messages.cooldown")
      if message and message ~= "" then
        ba.messages.sendRaw(handle, message:gsub("{time}", tostring(cooldownRemaining)))
      end
      openMenu(nil, handle, waiting)
      return true
    end

    local previousVote = VoteState.getPlayerVote(waiting, handle)
    VoteState.castVote(waiting, handle, modifier)
    voteCooldowns[handle] = os.clock()
    openMenu(nil, handle, waiting)
    return true
  end

  return false
end

-- The single entry point both the lobby waiting-item click and the menu-action handler dispatch
-- through - mirrors legacy LuckyPillarsGame.handleVoteCommand's own context-or-not routing.
function M.handleVoteAction(handle, args)
  local session = ba.session.forPlayer(handle)
  if not session then
    return M.handleVoteCommandWithoutContext(handle, args)
  end

  local phase = session.phase()
  if phase == "PLAYING" or phase == "ENDING" or phase == "FINISHED" then
    return false
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
    return M.handleVoteAction(handle, { "menu", "modifiers" })
  end)
end

return M

-- Mirrors legacy VoteState.java. A vote state is a plain table, not an object.
local M = {}

function M.new(defaultModifier)
  return {
    defaultModifier = defaultModifier or "none",
    modifierVotes = {},
    playerVotes = {},
  }
end

function M.castVote(state, playerId, modifier)
  if not playerId or not modifier then
    return
  end
  local previous = state.playerVotes[playerId]
  state.playerVotes[playerId] = modifier

  if previous == modifier then
    return
  end
  if previous then
    state.modifierVotes[previous] = math.max(0, (state.modifierVotes[previous] or 0) - 1)
  end
  state.modifierVotes[modifier] = (state.modifierVotes[modifier] or 0) + 1
end

function M.getVotes(state, modifier)
  if not modifier then
    return 0
  end
  return state.modifierVotes[modifier] or 0
end

function M.getPlayerVote(state, playerId)
  if not playerId then
    return nil
  end
  return state.playerVotes[playerId]
end

function M.clearPlayerVotes(state, playerId)
  if not playerId then
    return
  end
  local modifier = state.playerVotes[playerId]
  state.playerVotes[playerId] = nil
  if not modifier then
    return
  end
  local remaining = (state.modifierVotes[modifier] or 0) - 1
  if remaining > 0 then
    state.modifierVotes[modifier] = remaining
  else
    state.modifierVotes[modifier] = nil
  end
end

function M.resolveWinner(state)
  local maxVotes = -1
  local winningModifier = nil
  local tie = false
  local any = false
  for modifier, count in pairs(state.modifierVotes) do
    any = true
    if count > maxVotes then
      maxVotes = count
      winningModifier = modifier
      tie = false
    elseif count == maxVotes then
      tie = true
    end
  end

  if not any or not winningModifier or tie then
    return state.defaultModifier
  end
  return winningModifier
end

function M.hasVotes(state)
  for _, count in pairs(state.modifierVotes) do
    if count > 0 then
      return true
    end
  end
  return false
end

function M.getVoterIds(state)
  local ids = {}
  for playerId in pairs(state.playerVotes) do
    ids[#ids + 1] = playerId
  end
  return ids
end

return M

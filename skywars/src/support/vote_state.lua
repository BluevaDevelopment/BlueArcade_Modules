-- Mirrors legacy VoteState.java. A vote state is a plain table, nested per category
-- (chests/hearts/time/weather) - same shape as capture_the_wool's own 3-category version, with
-- a 4th "chests" category added.
local M = {}

function M.new(defaults)
  return {
    defaults = defaults or {},
    votes = { chests = {}, hearts = {}, time = {}, weather = {} },
    playerVotes = {},
  }
end

function M.castVote(state, playerId, category, option)
  if not playerId or not category or not option then
    return
  end
  local playerMap = state.playerVotes[playerId]
  if not playerMap then
    playerMap = {}
    state.playerVotes[playerId] = playerMap
  end
  local previous = playerMap[category]
  playerMap[category] = option

  if previous == option then
    return
  end
  local categoryVotes = state.votes[category]
  if previous then
    categoryVotes[previous] = math.max(0, (categoryVotes[previous] or 0) - 1)
  end
  categoryVotes[option] = (categoryVotes[option] or 0) + 1
end

function M.getVotes(state, category, option)
  if not category or not option then
    return 0
  end
  return (state.votes[category] or {})[option] or 0
end

function M.getPlayerVote(state, playerId, category)
  if not playerId or not category then
    return nil
  end
  local playerMap = state.playerVotes[playerId]
  return playerMap and playerMap[category] or nil
end

function M.clearPlayerVotes(state, playerId)
  if not playerId then
    return
  end
  local playerMap = state.playerVotes[playerId]
  state.playerVotes[playerId] = nil
  if not playerMap then
    return
  end
  for category, option in pairs(playerMap) do
    local categoryVotes = state.votes[category]
    local remaining = (categoryVotes[option] or 0) - 1
    if remaining > 0 then
      categoryVotes[option] = remaining
    else
      categoryVotes[option] = nil
    end
  end
end

function M.getVoterIds(state)
  local ids = {}
  for playerId in pairs(state.playerVotes) do
    ids[#ids + 1] = playerId
  end
  return ids
end

function M.hasVotes(state, category)
  local categoryVotes = state.votes[category]
  if not categoryVotes then
    return false
  end
  for _, count in pairs(categoryVotes) do
    if count > 0 then
      return true
    end
  end
  return false
end

function M.resolveWinner(state, category)
  local categoryVotes = state.votes[category]
  if not categoryVotes then
    return state.defaults[category]
  end

  local maxVotes = -1
  local winner = nil
  local tie = false
  for option, count in pairs(categoryVotes) do
    if count > maxVotes then
      maxVotes = count
      winner = option
      tie = false
    elseif count == maxVotes then
      tie = true
    end
  end

  if not winner then
    return state.defaults[category]
  end
  if tie then
    return state.defaults[category] or winner
  end
  return winner
end

return M

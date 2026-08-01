--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy VoteState.java - a single-category "theme" vote, same shape as lucky_pillars'
-- own single-category vote_state.lua.
local M = {}

function M.new(defaultTheme)
  return {
    defaultTheme = defaultTheme or "random",
    themeVotes = {},
    playerVotes = {},
  }
end

function M.castVote(state, playerId, theme)
  if not playerId or not theme then
    return
  end
  local previous = state.playerVotes[playerId]
  state.playerVotes[playerId] = theme

  if previous == theme then
    return
  end
  if previous then
    state.themeVotes[previous] = math.max(0, (state.themeVotes[previous] or 0) - 1)
  end
  state.themeVotes[theme] = (state.themeVotes[theme] or 0) + 1
end

function M.getVotes(state, theme)
  if not theme then
    return 0
  end
  return state.themeVotes[theme] or 0
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
  local theme = state.playerVotes[playerId]
  state.playerVotes[playerId] = nil
  if not theme then
    return
  end
  local remaining = (state.themeVotes[theme] or 0) - 1
  if remaining > 0 then
    state.themeVotes[theme] = remaining
  else
    state.themeVotes[theme] = nil
  end
end

function M.resolveWinner(state)
  local maxVotes = -1
  local winningTheme = nil
  local tie = false
  local any = false
  for theme, count in pairs(state.themeVotes) do
    any = true
    if count > maxVotes then
      maxVotes = count
      winningTheme = theme
      tie = false
    elseif count == maxVotes then
      tie = true
    end
  end

  if not any or not winningTheme or tie then
    return state.defaultTheme
  end
  return winningTheme
end

function M.hasVotes(state)
  for _, count in pairs(state.themeVotes) do
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

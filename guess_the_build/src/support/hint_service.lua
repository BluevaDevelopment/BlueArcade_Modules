-- Mirrors legacy GuessTheBuildHintService.java. characterCountBroadcasted lives on
-- session.state (not a module-level local like the Java field) since it must reset per round,
-- per-session - a module-level Lua local would leak across every live arena this module runs.
local M = {}

local function formatTime(totalSeconds)
  return string.format("%02d:%02d", math.floor(totalSeconds / 60), totalSeconds % 60)
end

local function trim(s)
  return s:match("^%s*(.-)%s*$") or s
end

local function countLetters(theme)
  local count = 0
  for i = 1, #theme do
    if theme:sub(i, i):match("%S") then
      count = count + 1
    end
  end
  return count
end

function M.buildHintString(theme, revealedIndices)
  local revealed = {}
  for _, idx in ipairs(revealedIndices) do
    revealed[idx] = true
  end

  local parts = {}
  for i = 1, #theme do
    local c = theme:sub(i, i)
    if c:match("%s") then
      parts[#parts + 1] = "  "
    elseif revealed[i] then
      parts[#parts + 1] = c .. " "
    else
      parts[#parts + 1] = "_ "
    end
  end
  return trim(table.concat(parts))
end

function M.reset(session)
  session.state.characterCountBroadcasted = false
end

local function revealRandomLetter(session, theme)
  local hidden = {}
  for i = 1, #theme do
    local c = theme:sub(i, i)
    if not c:match("%s") then
      local alreadyRevealed = false
      for _, idx in ipairs(session.state.revealedLetterIndices) do
        if idx == i then
          alreadyRevealed = true
          break
        end
      end
      if not alreadyRevealed then
        hidden[#hidden + 1] = i
      end
    end
  end

  if #hidden > 2 then
    local pick = hidden[math.random(#hidden)]
    table.insert(session.state.revealedLetterIndices, pick)
  end
end

local function sendActionBars(session, theme)
  local timeStr = formatTime(session.state.buildTimeLeft)
  local hintString = M.buildHintString(theme, session.state.revealedLetterIndices)
  local builder = session.state.currentBuilder

  for _, handle in ipairs(session.players()) do
    if handle == builder then
      local builderMessage = session.config.translation(handle, "game.action_bar.builder")
        or "<aqua>You are building:</aqua> <green>{theme}</green> <dark_gray>•</dark_gray> <aqua>Time:</aqua> <yellow>{time}</yellow>"
      session.messages.sendActionBar(handle, builderMessage:gsub("{theme}", theme):gsub("{time}", timeStr))
    elseif M.hasGuessed(session, handle) then
      local guessedMessage = session.config.translation(handle, "game.action_bar.guessed")
        or "<aqua>Theme:</aqua> <green>{theme}</green> <dark_gray>•</dark_gray> <aqua>Status:</aqua> <green>Guessed!</green>"
      session.messages.sendActionBar(handle, guessedMessage:gsub("{theme}", theme))
    else
      local guessingTemplate = session.config.translation(handle, "game.action_bar.guessing")
        or "<aqua>Theme:</aqua> <white>{hint}</white> <dark_gray>•</dark_gray> <aqua>Time:</aqua> <yellow>{time}</yellow>"
      session.messages.sendActionBar(handle, guessingTemplate:gsub("{hint}", hintString):gsub("{time}", timeStr))
    end
  end
end

function M.hasGuessed(session, handle)
  for _, guessed in ipairs(session.state.whoGuessed) do
    if guessed == handle then
      return true
    end
  end
  return false
end

function M.tick(session)
  local timeLeft = session.state.buildTimeLeft
  if timeLeft <= 0 then
    return
  end

  local charCountBroadcastAt = session.config.getInt("timers.character_count_broadcast_seconds", 90)
  local hintRevealStart = session.config.getInt("timers.hint_reveal_start_seconds", 70)
  local hintInterval = session.config.getInt("timers.hint_reveal_interval_seconds", 10)

  local theme = session.state.currentTheme
  if not theme or theme == "" then
    return
  end

  if not session.state.characterCountBroadcasted and timeLeft <= charCountBroadcastAt then
    session.state.characterCountBroadcasted = true
    for _, handle in ipairs(session.players()) do
      local msg = session.config.translation(handle, "game.character_count")
      if msg then
        session.messages.sendRaw(handle, msg:gsub("{count}", tostring(countLetters(theme))))
      end
    end
  end

  if timeLeft <= hintRevealStart and timeLeft % hintInterval == 0 then
    revealRandomLetter(session, theme)
  end

  sendActionBars(session, theme)
end

return M

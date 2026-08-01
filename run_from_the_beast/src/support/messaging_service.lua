-- Mirrors legacy RunFromTheBeastMessagingService.java.
local M = {}

local function formatCountdownTime(seconds)
  local safe = math.max(0, seconds)
  return string.format("%02d:%02d", math.floor(safe / 60), safe % 60)
end

function M.sendDescription(session)
  for _, handle in ipairs(session.players()) do
    for _, line in ipairs(session.config.translationList(handle, "description")) do
      session.messages.sendRaw(handle, line)
    end
  end
end

function M.sendActionBar(session, handle, placeholders)
  local template = session.coreConfig.language(handle, "action_bar.in_game.global")
  if template then
    local formatted = template
      :gsub("{time}", formatCountdownTime(session.state.timeLeftSeconds))
      :gsub("{round}", tostring(session.currentRound))
      :gsub("{round_max}", tostring(session.maxRounds))
    session.messages.sendActionBar(handle, formatted)
  end
  session.scoreboard.updateModule(handle, placeholders)
end

function M.buildCustomPlaceholders(session, handle, beast, runnersAlive)
  return {
    beast = beast and session.player.name(beast) or "-",
    runners_alive = tostring(runnersAlive),
    release_time = tostring(math.max(session.state.releaseTimeSeconds, 0)),
    checkpoint_uses = tostring(session.state.checkpointUses[handle] or 0),
    time = formatCountdownTime(session.state.timeLeftSeconds),
  }
end

function M.sendBeastTitle(session, beast)
  local title = session.config.translation(beast, "titles.beast.title")
  local subtitle = session.config.translation(beast, "titles.beast.subtitle")
  if (not title or title == "") and (not subtitle or subtitle == "") then
    return
  end
  session.titles.sendRaw(beast, title or "", subtitle or "", 0, 40, 10)
end

local function applyPlaceholders(text, placeholders)
  if not text then
    return text
  end
  for key, value in pairs(placeholders) do
    text = text:gsub("{" .. key .. "}", value)
  end
  return text
end

function M.sendOutcomeMessage(session, multilinePath, fallbackPath, placeholders)
  for _, handle in ipairs(session.players()) do
    local lines = session.config.translationList(handle, multilinePath)
    if #lines > 0 then
      for _, line in ipairs(lines) do
        session.messages.sendRaw(handle, applyPlaceholders(line, placeholders))
      end
    elseif fallbackPath then
      local fallback = session.config.translation(handle, fallbackPath)
      if fallback then
        session.messages.sendRaw(handle, applyPlaceholders(fallback, placeholders))
      end
    end
  end
end

function M.sendVictoryTitles(session, basePath, placeholders)
  local rawTitle = session.config.translation(nil, basePath .. ".title")
  local rawSubtitle = session.config.translation(nil, basePath .. ".subtitle")
  if (not rawTitle or rawTitle == "") and (not rawSubtitle or rawSubtitle == "") then
    return
  end
  local title = applyPlaceholders(rawTitle, placeholders) or ""
  local subtitle = applyPlaceholders(rawSubtitle, placeholders) or ""
  for _, handle in ipairs(session.players()) do
    session.titles.sendRaw(handle, title, subtitle, 0, 60, 20)
  end
end

function M.showFinalScoreboard(session, path, placeholders)
  for _, handle in ipairs(session.players()) do
    session.scoreboard.showFinalModule(handle, path, placeholders)
  end
end

function M.broadcastBeastKill(session, victim, beast)
  local messages = session.config.translationList(nil, "messages.deaths.killed_by_beast")
  if #messages == 0 then
    return
  end
  local message = messages[math.random(#messages)]
    :gsub("{victim}", session.player.name(victim))
    :gsub("{beast}", session.player.name(beast))
  for _, handle in ipairs(session.players()) do
    session.messages.sendRaw(handle, message)
  end
end

function M.getRandomMessage(session, path)
  local messages = session.config.translationList(nil, path)
  if #messages == 0 then
    return nil
  end
  return messages[math.random(#messages)]
end

return M

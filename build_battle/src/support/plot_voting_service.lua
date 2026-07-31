-- Mirrors legacy BuildBattlePlotVotingService.java.
local PlotService = require("support.plot_service")

local M = {}

local VOTE_ITEM_KEYS = { "super_poop", "poop", "ok", "good", "awesome", "god" }

local function loadVoteItemsConfig(session)
  local items = {}
  for _, key in ipairs(VOTE_ITEM_KEYS) do
    local prefix = "vote_items." .. key
    items[key] = {
      enabled = session.config.getBoolean(prefix .. ".enabled", false),
      material = session.config.getString(prefix .. ".material"),
      slot = session.config.getInt(prefix .. ".slot", 0),
      displayName = session.config.getString(prefix .. ".display_name"),
      lore = session.config.getStringList(prefix .. ".lore"),
      points = session.config.getInt(prefix .. ".points", 0),
    }
  end
  return items
end

local function resolveVoteEntry(session, material)
  for _, entry in pairs(loadVoteItemsConfig(session)) do
    if entry.material and entry.material:upper() == material then
      return entry
    end
  end
  return nil
end

local function giveVoteItems(session, handle)
  for _, config in pairs(loadVoteItemsConfig(session)) do
    if config.enabled and config.material and config.slot >= 0 and config.slot <= 8 then
      session.player.giveEnchantedItem(handle, config.material, 1, config.slot, nil, nil, false, config.displayName, config.lore)
    end
  end
end

local function updateVotingScoreboard(session, builder)
  local placeholders = {
    current = tostring(session.state.currentPlotIndex + 1),
    total = tostring(#session.players()),
    builder = session.player.name(builder),
  }
  for _, handle in ipairs(session.players()) do
    session.scoreboard.update(handle, "scoreboard.voting", placeholders)
  end
end

local function applyDefaultVotesForCurrentPlot(session, builder)
  local defaultPoints = session.config.getInt("voting.default_vote_points", 3)
  for _, handle in ipairs(session.players()) do
    if handle ~= builder and not session.state.votedCurrentPlot[handle] then
      session.state.plotVotes[builder] = session.state.plotVotes[builder] or {}
      session.state.plotVotes[builder][handle] = defaultPoints
    end
  end
end

local function endVotingPhase(session, outcomeService)
  session.state.phase = "ENDED"
  for _, handle in ipairs(session.players()) do
    local message = session.config.translation(handle, "plot_voting.voting_ended")
    if message then
      session.messages.sendRaw(handle, message)
    end
  end
  outcomeService.endGame(session)
end

local function advanceToNextPlot(session, outcomeService)
  local players = session.players()
  if session.state.currentPlotIndex >= #players then
    endVotingPhase(session, outcomeService)
    return
  end

  local builder = players[session.state.currentPlotIndex + 1]
  local plot = session.state.playerPlotSpawn[builder]
  if not plot and #session.state.plotSpawns > 0 then
    plot = session.state.plotSpawns[(session.state.currentPlotIndex % #session.state.plotSpawns) + 1]
  end

  session.state.votedCurrentPlot = {}

  local plotTime = session.state.plotTimeOverride[builder]
  local plotWeather = session.state.plotWeatherOverride[builder]

  for _, handle in ipairs(players) do
    session.player.clearInventory(handle)
    session.player.setAllowFlight(handle, true)
    session.player.setFlying(handle, true)

    if plotTime then
      session.player.setTime(handle, plotTime, false)
    else
      session.player.resetTime(handle)
    end
    if plotWeather then
      session.player.setWeather(handle, plotWeather)
    else
      session.player.resetWeather(handle)
    end

    if plot then
      session.player.teleport(handle, PlotService.centerLocation(plot))
    end

    local header = session.config.translation(handle, "plot_voting.header")
    if header then
      session.messages.sendRaw(handle, header:gsub("{player}", session.player.name(builder)))
    end

    if handle ~= builder then
      giveVoteItems(session, handle)
    end
  end

  updateVotingScoreboard(session, builder)

  local plotDisplaySeconds = session.config.getInt("voting.plot_display_seconds", 10)
  local taskId = "arena_" .. session.arenaId .. "_build_battle_plot_timer"
  local ticksLeft = plotDisplaySeconds

  session.scheduler.runTimer(taskId, function()
    ticksLeft = ticksLeft - 1
    if ticksLeft <= 0 then
      session.scheduler.cancelTask(taskId)
      applyDefaultVotesForCurrentPlot(session, builder)
      session.state.currentPlotIndex = session.state.currentPlotIndex + 1
      advanceToNextPlot(session, outcomeService)
    end
  end, 20, 20)
end

function M.startPlotVoting(session, outcomeService)
  local players = session.players()
  if #players == 0 then
    outcomeService.endGame(session)
    return
  end

  session.state.currentPlotIndex = 0
  session.state.votedCurrentPlot = {}

  for _, handle in ipairs(players) do
    local title = session.config.translation(handle, "titles.voting_started.title")
    local subtitle = session.config.translation(handle, "titles.voting_started.subtitle")
    if title and subtitle then
      session.titles.sendRaw(handle, title, subtitle, 0, 30, 10)
    end
  end

  advanceToNextPlot(session, outcomeService)
end

function M.handleVoteItemClick(session, voter, material)
  if session.state.phase ~= "PLOT_VOTING" then
    return
  end
  if not material or material == "AIR" then
    return
  end

  local players = session.players()
  if session.state.currentPlotIndex < 0 or session.state.currentPlotIndex >= #players then
    return
  end

  local builder = players[session.state.currentPlotIndex + 1]
  if not builder or voter == builder then
    local msg = session.config.translation(voter, "plot_voting.self_voting_disabled")
    if msg then
      session.messages.sendRaw(voter, msg)
    end
    return
  end

  if session.state.votedCurrentPlot[voter] then
    return
  end

  local entry = resolveVoteEntry(session, material)
  if not entry or entry.points <= 0 then
    return
  end

  session.state.plotVotes[builder] = session.state.plotVotes[builder] or {}
  session.state.plotVotes[builder][voter] = entry.points
  session.state.votedCurrentPlot[voter] = true
  session.player.clearInventory(voter)

  local msg = session.config.translation(voter, "plot_voting.vote_cast")
  if msg then
    session.messages.sendRaw(voter, msg:gsub("{rating_name}", entry.displayName or tostring(entry.points)))
  end
end

return M

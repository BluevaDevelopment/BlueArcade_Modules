-- Mirrors legacy SpeedBuildersJudgingService.java. startNextRound is passed in by game_manager.lua
-- rather than required directly, to avoid a require() cycle (game_manager already requires this
-- file).
local worldSupport = require("support.world_support")
local guardianService = require("support.guardian_service")
local scoreboardService = require("support.scoreboard_service")

local M = {}

local function isPerfectScore(score)
  return score >= 99.999
end

local function allAlivePlayersPerfect(session, state)
  local alive = session.alivePlayers()
  if #alive == 0 then
    return false
  end
  for _, handle in ipairs(alive) do
    if not state.perfectPlayers[handle] then
      return false
    end
  end
  return true
end

-- evaluateBuild - the "early perfect" check fired shortly after every block break/place during the
-- BUILDING phase (see listener.lua's scheduleEvaluate). Ends the round immediately once every
-- alive player has hit a perfect score.
function M.evaluateBuild(session, state, handle, startNextRound)
  if state.ended or state.phase ~= "BUILDING" or state.perfectPlayers[handle] then
    return
  end
  local origin = worldSupport.getBuildOrigin(state, handle)
  if not origin or not state.currentStructure then
    return
  end

  local yaw = state.playerPlotYaw[handle] or 0
  local score = session.structure.evaluate(origin, state.currentStructure.id, yaw, true)
  state.lastScore[handle] = score.percentage
  scoreboardService.update(session, state)

  if not score.perfect then
    return
  end

  state.perfectPlayers[handle] = true
  state.perfectBuilds[handle] = (state.perfectBuilds[handle] or 0) + 1

  local title = session.config.translation(handle, "titles.perfect.title")
  local subtitle = session.config.translation(handle, "titles.perfect.subtitle")
  if title and subtitle then
    session.titles.sendRaw(handle, title, subtitle, 0, 20, 10)
  end
  session.sounds.playDirect(handle, "ENTITY_PLAYER_LEVELUP", 1.0, 1.5)

  local broadcast = session.config.translation(handle, "messages.perfect_build.broadcast")
  if broadcast then
    for _, viewer in ipairs(session.players()) do
      session.messages.sendRaw(viewer, broadcast:gsub("{player}", session.player.name(handle)))
    end
  end

  if allAlivePlayersPerfect(session, state) then
    local allPerfect = session.config.translation(handle, "messages.all_perfect.broadcast")
    if allPerfect then
      for _, viewer in ipairs(session.players()) do
        session.messages.sendRaw(viewer, allPerfect)
      end
    end
    session.scheduler.cancelArenaTasks()
    session.scheduler.runLater("arena_" .. session.arenaId .. "_speed_builders_all_perfect", function()
      startNextRound(session, state)
    end, 60)
  end
end

local function eliminatePlayer(session, state, handle, score)
  session.eliminate(handle, "lowest_score")
  session.setSpectating(handle, true)
  session.player.clearInventory(handle)

  local title = session.config.translation(handle, "titles.elimination.title")
  local subtitle = session.config.translation(handle, "titles.elimination.subtitle")
  if title and subtitle then
    session.titles.sendRaw(handle, title, subtitle:gsub("{score}", string.format("%.0f", score)), 0, 30, 10)
  end

  local broadcast = session.config.translation(handle, "messages.elimination.broadcast")
  if broadcast then
    local text = broadcast:gsub("{player}", session.player.name(handle)):gsub("{score}", string.format("%.0f", score))
    for _, viewer in ipairs(session.players()) do
      session.messages.sendRaw(viewer, text)
    end
  end
end

function M.endGameWithWinner(session)
  local alive = session.alivePlayers()
  if #alive == 1 then
    local winner = alive[1]
    session.setWinner(winner)
    for _, viewer in ipairs(session.players()) do
      local title = session.config.translation(viewer, "titles.winner.title")
      local subtitle = session.config.translation(viewer, "titles.winner.subtitle")
      if title and subtitle then
        session.titles.sendRaw(viewer, title, subtitle:gsub("{player}", session.player.name(winner)), 0, 60, 20)
      end
    end
    local broadcast = session.config.translation(winner, "messages.game_winner.broadcast")
    if broadcast then
      local text = broadcast:gsub("{player}", session.player.name(winner))
      for _, viewer in ipairs(session.players()) do
        session.messages.sendRaw(viewer, text)
      end
    end
  end
  session.scheduler.runLater("arena_" .. session.arenaId .. "_speed_builders_end", function()
    session.endGame()
  end, 60)
end

local function continueAfterJudging(session, state, startNextRound)
  local alive = session.alivePlayers()
  if #alive <= 1 then
    if #alive == 1 then
      session.setWinner(alive[1])
    end
    session.scheduler.runLater("arena_" .. session.arenaId .. "_speed_builders_end", function()
      session.endGame()
    end, 60)
    return
  end

  local betweenRounds = session.config.getInt("time.between_rounds", 3)
  session.scheduler.runLater("arena_" .. session.arenaId .. "_speed_builders_next_round", function()
    startNextRound(session, state)
  end, betweenRounds * 20)
end

-- evaluateBuildsAndEliminate - the real round-end judging pass: scores every alive player once
-- more (mob-inclusive this time, unlike evaluateBuild's own early check), eliminates the single
-- lowest non-perfect scorer (ties broken by iteration order, matching legacy's own
-- Map.Entry-iteration tie-break), and continues to the next round or ends the game.
function M.evaluateBuildsAndEliminate(session, state, startNextRound)
  if state.ended then
    return
  end
  if not state.currentStructure then
    M.endGameWithWinner(session)
    return
  end

  local scores = {}
  local scoreCount = 0
  for _, handle in ipairs(session.alivePlayers()) do
    local origin = worldSupport.getBuildOrigin(state, handle)
    if origin then
      local yaw = state.playerPlotYaw[handle] or 0
      local score = session.structure.evaluate(origin, state.currentStructure.id, yaw, true)
      state.lastScore[handle] = score.percentage
      scores[handle] = score.percentage
      scoreCount = scoreCount + 1
    end
  end

  if scoreCount == 0 then
    M.endGameWithWinner(session)
    return
  end

  local aliveCount = #session.alivePlayers()
  local allAliveScored = scoreCount == aliveCount
  local allPerfect = allAliveScored
  if allPerfect then
    for _, score in pairs(scores) do
      if not isPerfectScore(score) then
        allPerfect = false
        break
      end
    end
  end
  if allPerfect then
    continueAfterJudging(session, state, startNextRound)
    return
  end

  local lowestHandle, lowestScore = nil, 101.0
  for handle, score in pairs(scores) do
    if not isPerfectScore(score) and score < lowestScore then
      lowestScore = score
      lowestHandle = handle
    end
  end
  if lowestHandle then
    guardianService.aimAtPlayerPlot(session, state, lowestHandle)
    guardianService.explodePlayerPlot(session, state, lowestHandle)
    eliminatePlayer(session, state, lowestHandle, lowestScore)
  end

  continueAfterJudging(session, state, startNextRound)
end

return M

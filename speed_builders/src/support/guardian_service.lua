-- Mirrors legacy GuardianService.java. Real mechanics (entity control, explosion shard physics,
-- particle beams) live in session.guardian (GuardianBinding.kt) - this file owns the business
-- decisions legacy mixed into the same class: orbit angle bookkeeping, which alive player to look
-- at, and the per-tick watch/beam-draw scheduling loops.
local plotService = require("support.plot_service")

local M = {}

local function homeLocation(session, state)
  local showcase = state.showcasePlot
  if not showcase then
    return nil
  end
  local center = plotService.regionCenter(showcase.min, showcase.max, 0.0)
  local maxY = math.max(showcase.min.y, showcase.max.y)
  local height = math.max(1, session.config.getInt("guardian.height_above_showcase", 5))
  center.y = math.min(session.world.maxHeight() - 2.0, maxY + height)
  return center
end

local function findLookTarget(session, state)
  local alive = session.alivePlayers()
  if #alive > 0 then
    local index = (math.floor(os.clock() * 1000 / 1500) % #alive) + 1
    local handle = alive[index]
    local area = state.playerBuildArea[handle]
    if area then
      return plotService.regionCenter(area.min, area.max, 2.0)
    end
    local plot = state.playerPlot[handle]
    if plot then
      return plotService.regionCenter(plot.min, plot.max, 2.0)
    end
  end
  local showcase = state.showcasePlot
  return showcase and plotService.regionCenter(showcase.min, showcase.max, 2.0) or nil
end

local function watchTaskId(session)
  return "arena_" .. session.arenaId .. "_speed_builders_guardian_watch"
end

local function beamTaskId(session)
  return "arena_" .. session.arenaId .. "_speed_builders_guardian_beam"
end

function M.ensureAtShowcase(session, state)
  local home = homeLocation(session, state)
  if not home then
    return
  end
  session.guardian.spawn(home)
end

function M.startWatchTask(session, state)
  local taskId = watchTaskId(session)
  session.scheduler.cancelTask(taskId)
  session.scheduler.runTimer(taskId, function()
    if state.ended then
      session.scheduler.cancelTask(taskId)
      return
    end
    local home = homeLocation(session, state)
    if not home then
      return
    end
    if not session.guardian.isValid() then
      session.guardian.spawn(home)
    end
    if not session.guardian.isValid() then
      return
    end

    local isBuilding = state.phase == "BUILDING"
    if isBuilding then
      local degreesPerTick = math.max(0.1, session.config.getInt("guardian.orbit_degrees_per_tick", 3))
      state.guardianOrbitAngle = (state.guardianOrbitAngle or 0) + math.rad(degreesPerTick)
    end
    local radius = isBuilding and math.max(0, session.config.getInt("guardian.orbit_radius", 4)) or 0

    local target
    if state.guardianBeamTarget then
      target = state.guardianBeamTarget
      radius = 0
    else
      target = findLookTarget(session, state)
    end

    session.guardian.updatePosition(home, state.guardianOrbitAngle or 0, radius, target)
  end, 1, 1)
end

local function startBeamParticles(session, state, target)
  local taskId = beamTaskId(session)
  session.scheduler.cancelTask(taskId)
  local duration = math.max(10, session.config.getInt("guardian.beam_ticks", 50))
  local ticks = 0
  session.scheduler.runTimer(taskId, function()
    ticks = ticks + 1
    if not session.guardian.isValid() or ticks >= duration then
      session.scheduler.cancelTask(taskId)
      state.guardianBeamTarget = nil
      session.guardian.clearBeamTarget()
      return
    end
    session.guardian.drawBeamTick(target)
  end, 1, 1)
end

function M.aimAtPlayerPlot(session, state, handle)
  local plot = state.playerPlot[handle]
  if not plot then
    return
  end
  local target = plotService.regionCenter(plot.min, plot.max, 2.0)
  state.guardianBeamTarget = target
  session.guardian.aimAndAttack(target)
  startBeamParticles(session, state, target)
end

function M.explodePlayerPlot(session, state, handle)
  local plot = state.playerPlot[handle]
  if not plot then
    return
  end
  local maxShards = math.max(1, session.config.getInt("guardian.explosion_max_shards", 220))
  local horizontalPower = math.max(0, session.config.getInt("guardian.explosion_horizontal_power", 8)) / 10.0
  local upwardPower = math.max(0, session.config.getInt("guardian.explosion_upward_power", 7)) / 10.0
  session.guardian.explodePlot(plot.min, plot.max, maxShards, horizontalPower, upwardPower)

  local lifetime = math.max(10, session.config.getInt("guardian.explosion_shard_lifetime_ticks", 50))
  session.scheduler.runLater("arena_" .. session.arenaId .. "_speed_builders_plot_explosion_" .. handle, function()
    session.guardian.clearShards()
  end, lifetime)
end

function M.showJudgingAnimation(session)
  for _, handle in ipairs(session.players()) do
    session.guardian.showJudgingAnimationFor(handle)
  end
end

function M.remove(session, state)
  session.scheduler.cancelTask(watchTaskId(session))
  session.scheduler.cancelTask(beamTaskId(session))
  state.guardianBeamTarget = nil
  session.guardian.remove()
end

return M

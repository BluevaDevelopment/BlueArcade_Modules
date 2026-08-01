-- Drives the real per-world WorldBorder directly (session.world.border), no cached reference needed.
local M = {}

local function getBounds(session)
  local min = session.arena.boundsMin()
  local max = session.arena.boundsMax()
  if not min or not max then
    return nil
  end
  return min, max
end

local function resolveCenter(session)
  local min, max = getBounds(session)
  if min then
    return { x = (min.x + max.x) / 2.0, y = (min.y + max.y) / 2.0, z = (min.z + max.z) / 2.0 }
  end
  local players = session.players()
  if #players == 0 then
    return nil
  end
  return session.player.location(players[1])
end

local function resolveMaxRadius(session, center)
  if not center then
    return session.config.getDouble("storm.default_radius", 80.0)
  end
  local min, max = getBounds(session)
  if min then
    local halfX = math.abs(max.x - min.x) / 2.0
    local halfZ = math.abs(max.z - min.z) / 2.0
    return math.max(1.0, math.min(halfX, halfZ))
  end
  return session.config.getDouble("storm.default_radius", 80.0)
end

local function getStages(session)
  local defaultStandby = math.max(0, session.config.getInt("storm.standby_seconds", 10))
  local stages = {}
  for _, line in ipairs(session.config.getStringList("storm.stages")) do
    local parts = {}
    for part in line:gmatch("[^:]+") do
      parts[#parts + 1] = part
    end
    if #parts >= 3 then
      local radiusPercent = tonumber(parts[1])
      local duration = tonumber(parts[2])
      local damage = tonumber(parts[3])
      local standby = parts[4] and tonumber(parts[4]) or defaultStandby
      if radiusPercent and duration and damage then
        stages[#stages + 1] = {
          radiusPercent = math.max(0.0, radiusPercent),
          durationSeconds = math.max(1, math.floor(duration)),
          damagePerSecond = math.max(0.0, damage),
          standbySeconds = math.max(0, math.floor(standby)),
        }
      end
    end
  end
  return stages
end

local function resolveNextStageIndex(currentStageIndex, stages)
  local nextIndex = currentStageIndex + 1
  if nextIndex >= #stages then
    return #stages
  end
  return nextIndex
end

local function resolveStandbySeconds(session, stages)
  local nextIndex = session.state.stormNextStageIndex
  if nextIndex <= session.state.stormStageIndex or nextIndex >= #stages then
    return 0
  end
  -- stages is 0-indexed conceptually (matching legacy), Lua arrays are 1-indexed.
  return math.max(0, stages[nextIndex + 1].standbySeconds)
end

local function resolveInitialStandbySeconds(session, stages)
  if session.state.stormStageIndex == 0 and #stages > 0 then
    return math.max(0, stages[1].durationSeconds)
  end
  return resolveStandbySeconds(session, stages)
end

local function announceStormIncoming(session, stages)
  if not session.config.getBoolean("storm.announce_incoming", true) then
    return
  end
  local standbySeconds = session.state.stormPhaseDuration
  if standbySeconds <= 0 or session.state.stormNextStageIndex >= #stages then
    return
  end
  for _, handle in ipairs(session.players()) do
    local message = session.config.translation(handle, "messages.storm.incoming")
    if message and message ~= "" then
      session.messages.sendRaw(handle, message:gsub("{seconds}", tostring(standbySeconds)))
    end
  end
end

local function announceStormMoving(session)
  if not session.config.getBoolean("storm.announce_moving", true) then
    return
  end
  for _, handle in ipairs(session.players()) do
    local message = session.config.translation(handle, "messages.storm.moving")
    if message and message ~= "" then
      session.messages.sendRaw(handle, message)
    end
  end
end

local function initializeWorldBorder(session)
  if not session.state.stormCenter then
    return
  end
  session.world.border.setCenter(session.state.stormCenter)
  session.world.border.setSize(math.max(1.0, session.state.stormRadius * 2.0))
  session.world.border.setWarningDistance(0)
  session.world.border.setWarningTime(0)
  session.world.border.setDamageBuffer(0)
end

function M.initializeStorm(session)
  if not session.config.getBoolean("storm.enabled", true) then
    return
  end
  local stages = getStages(session)
  if #stages == 0 then
    return
  end

  local center = resolveCenter(session)
  session.state.stormCenter = center
  local maxRadius = resolveMaxRadius(session, center)
  session.state.stormMaxRadius = maxRadius

  session.state.stormRadius = maxRadius * stages[1].radiusPercent
  session.state.stormStageIndex = 0
  session.state.stormMoving = false
  session.state.stormNextStageIndex = resolveNextStageIndex(0, stages)
  session.state.stormPhaseTicks = 0
  session.state.stormPhaseDuration = resolveInitialStandbySeconds(session, stages)
  initializeWorldBorder(session)
  session.world.border.setDamageAmount(stages[1].damagePerSecond)
  announceStormIncoming(session, stages)
end

local function startStormMovement(session, stages)
  local nextIndex = session.state.stormNextStageIndex
  if nextIndex >= #stages then
    return
  end
  local stage = stages[nextIndex + 1]
  local targetRadius = session.state.stormMaxRadius * stage.radiusPercent
  session.world.border.setSize(math.max(1.0, targetRadius * 2.0), stage.durationSeconds)
  session.world.border.setDamageAmount(stage.damagePerSecond)

  session.state.stormMoving = true
  session.state.stormPhaseTicks = 0
  session.state.stormPhaseDuration = stage.durationSeconds
  announceStormMoving(session)
end

local function finishStormMovement(session, stages)
  local newStageIndex = session.state.stormNextStageIndex
  session.state.stormStageIndex = newStageIndex
  session.state.stormMoving = false
  session.state.stormPhaseTicks = 0
  session.state.stormNextStageIndex = resolveNextStageIndex(newStageIndex, stages)
  session.state.stormPhaseDuration = resolveStandbySeconds(session, stages)
  announceStormIncoming(session, stages)
end

local function tickStormPhase(session, stages)
  if session.state.stormNextStageIndex >= #stages then
    return
  end

  if session.state.stormMoving then
    session.state.stormPhaseTicks = session.state.stormPhaseTicks + 1
    if session.state.stormPhaseTicks >= session.state.stormPhaseDuration then
      finishStormMovement(session, stages)
    end
    return
  end

  local standbyDuration = session.state.stormPhaseDuration
  if standbyDuration <= 0 then
    startStormMovement(session, stages)
    return
  end

  session.state.stormPhaseTicks = session.state.stormPhaseTicks + 1
  if session.state.stormPhaseTicks >= standbyDuration then
    startStormMovement(session, stages)
  end
end

local function resolveCurrentRadius(session)
  return math.max(0.0, session.world.border.getSize() / 2.0)
end

local function spawnStormLightning(session)
  if not session.config.getBoolean("storm.lightning.enabled", true) then
    return
  end
  local interval = session.config.getInt("storm.lightning.interval_seconds", 3)
  if interval <= 0 then
    return
  end

  session.state.stormLightningTicks = (session.state.stormLightningTicks or 0) + 1
  if session.state.stormLightningTicks < interval then
    return
  end
  session.state.stormLightningTicks = 0

  local strikes = session.config.getInt("storm.lightning.strikes_per_wave", 3)
  local center = session.state.stormCenter
  if not center then
    return
  end

  local maxRadius = math.max(0.0, session.state.stormMaxRadius)
  local safeRadius = resolveCurrentRadius(session)
  local minRadius = math.min(maxRadius, math.max(safeRadius + 2.0, safeRadius))
  local maxPickRadius = math.max(minRadius, maxRadius + 1.0)

  for _ = 1, strikes do
    local radius = minRadius + math.random() * (maxPickRadius - minRadius)
    local angle = math.random() * math.pi * 2
    local strikeLocation = { x = center.x + radius * math.cos(angle), y = center.y, z = center.z + radius * math.sin(angle) }
    session.world.strikeLightningEffect(strikeLocation)
  end
end

function M.tickStorm(session)
  if not session.config.getBoolean("storm.enabled", true) then
    return
  end
  local stages = getStages(session)
  if #stages == 0 then
    return
  end

  if not session.state.stormCenter then
    M.initializeStorm(session)
  end

  tickStormPhase(session, stages)
  session.state.stormRadius = math.max(0.0, session.world.border.getSize() / 2.0)
  spawnStormLightning(session)
end

function M.clearWorldBorder(session)
  session.world.border.setSize(59999968.0)
  session.world.border.setDamageBuffer(5.0)
  session.world.border.setDamageAmount(0.2)
  session.world.border.setWarningDistance(5)
  session.world.border.setWarningTime(15)
end

return M

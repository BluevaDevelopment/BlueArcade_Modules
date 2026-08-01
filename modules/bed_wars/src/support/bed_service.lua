--  ____  _               _                      _
-- | __ )| |_   _  ___   / \   _ __ ___ __ _  __| | ___
-- |  _ \| | | | |/ _ \ / _ \ | '__/ __/ _` |/ _` |/ _ \
-- | |_) | | |_| |  __// ___ \| | | (_| (_| | (_| |  __/
-- |____/|_|\__,_|\___/_/   \_|_|  \___\__,_|\__,_|\___|
--
-- [!] Arcade by Blueva | https://blueva.net/store/blue-arcade [!]

-- Mirrors legacy BedService.java. BedDefinition/BedState are plain Lua tables. Real bed HEAD/FOOT
-- manipulation goes through `world.bedOtherHalf`/`removeBedPair`/`repairBed` bindings.
local M = {}

local function resolveDataBasePath(session, section)
  if session.dataAccess.hasGameData("game.play_area." .. section) then
    return "game.play_area." .. section
  end
  return "game." .. section
end

function M.loadBedDefinitions(session)
  local definitions = {}
  if not session.teams.isEnabled() then
    return definitions
  end

  local bedsBase = resolveDataBasePath(session, "beds")
  local teamIndex = 1
  for _, team in ipairs(session.teams.all()) do
    local teamId = team.id
    if teamId and teamId ~= "" then
      teamId = teamId:lower()
      local canonicalPath = bedsBase .. "." .. teamId
      local numericPath = bedsBase .. "." .. teamIndex
      local resolvedPath = nil
      if session.dataAccess.hasGameData(canonicalPath) then
        resolvedPath = canonicalPath
      elseif session.dataAccess.hasGameData(numericPath) then
        resolvedPath = numericPath
      end
      if resolvedPath then
        local bedLoc = session.dataAccess.getGameLocation(resolvedPath)
        if bedLoc then
          definitions[#definitions + 1] = { teamId = teamId, x = math.floor(bedLoc.x), y = math.floor(bedLoc.y), z = math.floor(bedLoc.z) }
        end
      end
    end
    teamIndex = teamIndex + 1
  end
  return definitions
end

local function locationsMatch(def, x, y, z)
  return def.x == x and def.y == y and def.z == z
end

function M.findBedAtLocation(session, x, y, z)
  for _, def in ipairs(session.state.beds) do
    if locationsMatch(def, x, y, z) then
      return def
    end
    local otherHalf = session.world.bedOtherHalf(def.x, def.y, def.z)
    if otherHalf and locationsMatch({ x = math.floor(otherHalf.x), y = math.floor(otherHalf.y), z = math.floor(otherHalf.z) }, x, y, z) then
      return def
    end
  end
  return nil
end

function M.isBedLocation(session, x, y, z)
  return M.findBedAtLocation(session, x, y, z) ~= nil
end

function M.isTeamBedIntact(session, teamId)
  if not teamId then return false end
  return (session.state.bedState[teamId:lower()] or "intact") == "intact"
end

local function hasTeamAnyPlayers(session, teamId)
  if not session.teams.isEnabled() then
    return true
  end
  for _, handle in ipairs(session.players()) do
    local pTeam = session.teams.forPlayer(handle)
    if pTeam and pTeam.id:lower() == teamId:lower() then
      return true
    end
  end
  return false
end

local function resolveTeamDisplay(session, teamId)
  if not session.teams.isEnabled() then
    return teamId
  end
  for _, team in ipairs(session.teams.all()) do
    if team.id and team.id:lower() == teamId:lower() then
      return team.displayName or teamId
    end
  end
  return teamId
end

function M.handleBedBreak(session, breakerHandle, x, y, z)
  local bedDef = M.findBedAtLocation(session, x, y, z)
  if not bedDef then
    return false
  end
  if not session.teams.isEnabled() then
    return false
  end

  local breakerTeam = session.teams.forPlayer(breakerHandle)
  if not breakerTeam then
    return false
  end
  if breakerTeam.id:lower() == bedDef.teamId then
    return false
  end

  if (session.state.bedState[bedDef.teamId] or "intact") == "destroyed" then
    return false
  end
  session.state.bedState[bedDef.teamId] = "destroyed"

  session.world.removeBedPair(bedDef.x, bedDef.y, bedDef.z)

  local hologram = session.state.bedHolograms[bedDef.teamId]
  if hologram then
    session.hologram.delete(hologram)
    session.state.bedHolograms[bedDef.teamId] = nil
  end

  local breakerName = session.player.name(breakerHandle)
  local victimTeamDisplay = resolveTeamDisplay(session, bedDef.teamId)

  for _, handle in ipairs(session.players()) do
    local template = session.config.translation(handle, "messages.bed.destroyed")
    if template then
      session.messages.sendRaw(handle, template:gsub("{player}", breakerName):gsub("{team}", victimTeamDisplay))
    end
  end

  for _, handle in ipairs(session.players()) do
    local pTeam = session.teams.forPlayer(handle)
    if pTeam and pTeam.id:lower() == bedDef.teamId then
      local title = session.config.translation(handle, "titles.bed_destroyed.title")
      local subtitle = session.config.translation(handle, "titles.bed_destroyed.subtitle")
      session.titles.sendRaw(handle, title, subtitle, 0, 60, 20)
    end
  end

  return true
end

function M.removeEmptyTeamBeds(session)
  if not session.teams.isEnabled() then
    return
  end
  local remaining = {}
  for _, def in ipairs(session.state.beds) do
    if hasTeamAnyPlayers(session, def.teamId) then
      remaining[#remaining + 1] = def
    else
      session.world.removeBedPair(def.x, def.y, def.z)
    end
  end
  session.state.beds = remaining
end

local function buildBedHologramLines(session, teamDisplay)
  local titleLine = session.config.translation(nil, "messages.bed.hologram_title") or "<red>\u{2764} BED \u{2764}</red>"
  local teamLine = (session.config.translation(nil, "messages.bed.hologram_label") or "<white>{team}</white>"):gsub("{team}", teamDisplay)
  local statusLine = session.config.translation(nil, "messages.bed.hologram_status") or "<green>Protected</green>"
  return { titleLine, teamLine, statusLine }
end

function M.spawnBedHolograms(session)
  for _, def in ipairs(session.state.beds) do
    if (session.state.bedState[def.teamId] or "intact") == "intact" and not session.state.bedHolograms[def.teamId] then
      if hasTeamAnyPlayers(session, def.teamId) then
        session.world.repairBed(def.x, def.y, def.z)
        local teamDisplay = resolveTeamDisplay(session, def.teamId)
        local holoLoc = { x = def.x + 0.5, y = def.y + 2.0, z = def.z + 0.5 }
        local lines = buildBedHologramLines(session, teamDisplay)
        local hologram = session.hologram.spawn(holoLoc, lines)
        if hologram then
          session.state.bedHolograms[def.teamId] = hologram
        end
      end
    end
  end
end

function M.clearBedHolograms(session)
  for teamId, hologram in pairs(session.state.bedHolograms) do
    session.hologram.delete(hologram)
    session.state.bedHolograms[teamId] = nil
  end
end

function M.getAliveTeamCount(session)
  if not session.teams.isEnabled() then
    return 0
  end
  local count = 0
  for _, team in ipairs(session.teams.all()) do
    if team.id and team.id ~= "" and M.isTeamAlive(session, team.id) then
      count = count + 1
    end
  end
  return count
end

function M.isTeamAlive(session, teamId)
  if session.teams.isEnabled() and not hasTeamAnyPlayers(session, teamId) then
    return false
  end
  if M.isTeamBedIntact(session, teamId) then
    return true
  end
  if not session.teams.isEnabled() then
    return false
  end
  for _, handle in ipairs(session.alivePlayers()) do
    local pTeam = session.teams.forPlayer(handle)
    if pTeam and pTeam.id:lower() == teamId:lower() then
      return true
    end
  end
  return false
end

return M

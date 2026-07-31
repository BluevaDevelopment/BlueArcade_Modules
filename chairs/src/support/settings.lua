local MUSIC_PLAYLIST = {
  "[NBS] modules/chairs/music/14th Song.nbs",
  "[NBS] modules/chairs/music/A Little Piece of Heaven.nbs",
  "[NBS] modules/chairs/music/A Nightmare Before Christmas.nbs",
  "[NBS] modules/chairs/music/Alan Walker - Alone.nbs",
  "[NBS] modules/chairs/music/Alan Walker - Fade.nbs",
  "[NBS] modules/chairs/music/Animals.nbs",
  "[NBS] modules/chairs/music/BlindingLights.nbs",
  "[NBS] modules/chairs/music/Gangnam Style.nbs",
  "[NBS] modules/chairs/music/Gravity Falls Theme.nbs",
  "[NBS] modules/chairs/music/I'm an Albatraoz.nbs",
  "[NBS] modules/chairs/music/Luis Fonsi - Despacito.nbs",
  "[NBS] modules/chairs/music/Mad World.nbs",
  "[NBS] modules/chairs/music/Nyan Cat.nbs",
  "[NBS] modules/chairs/music/OMFG - Hello.nbs",
  "[NBS] modules/chairs/music/fnafsong.nbs",
  "[NBS] modules/chairs/music/thriller.nbs",
}

local M = {}

function M.load(session)
  local settings = {}

  settings.initialMusicTime = session.config.getDouble("gameplay.initial_music_time", 6.0)
  settings.initialSitTime = session.config.getDouble("gameplay.initial_sit_time", 8.0)
  settings.musicTimeReduction = session.config.getDouble("gameplay.music_time_reduction", 0.35)
  settings.sitTimeReduction = session.config.getDouble("gameplay.sit_time_reduction", 0.4)
  settings.minimumMusicTime = session.config.getDouble("gameplay.minimum_music_time", 2.0)
  settings.minimumSitTime = session.config.getDouble("gameplay.minimum_sit_time", 2.0)
  settings.spawnHeightOffset = session.config.getDouble("seats.spawn_height_offset", 6.0)

  settings.seatTypes = session.config.getStringList("seats.types")
  if #settings.seatTypes == 0 then settings.seatTypes = { "MINECART" } end

  settings.warmupRounds = math.max(0, session.config.getInt("seats.warmup_rounds", 2))
  settings.warmupMaxPlayers = math.max(0, session.config.getInt("seats.warmup_max_players", 0))
  settings.seatReduction = math.max(1, session.config.getInt("seats.seat_reduction", 1))
  settings.minimumSeats = math.max(1, session.config.getInt("seats.minimum_seats", 1))

  settings.musicPlaylist = MUSIC_PLAYLIST

  return settings
end

local function isWarmupRound(settings, round, playersAlive)
  if settings.warmupRounds <= 0 or round > settings.warmupRounds then return false end
  return settings.warmupMaxPlayers <= 0 or playersAlive <= settings.warmupMaxPlayers
end

local function clampSeatCount(playersAlive, configuredSeats)
  return math.max(1, math.min(playersAlive, configuredSeats))
end

function M.resolveSeatCount(settings, round, playersAlive)
  if playersAlive <= 0 then return settings.minimumSeats end
  if isWarmupRound(settings, round, playersAlive) then
    return clampSeatCount(playersAlive, playersAlive)
  end
  return clampSeatCount(playersAlive, math.max(settings.minimumSeats, playersAlive - settings.seatReduction))
end

return M

-- Mirrors legacy GuessTheBuildThemeService.java. openThemeSelectionMenu takes an explicit onSelect
-- callback (mirroring Java's Consumer<GuessTheme>), invoked later from handleThemeAction once clicked.
local M = {}

local DIFFICULTY_POINTS = { EASY = 1, MEDIUM = 2, HARD = 3 }
local DIFFICULTIES = { "EASY", "MEDIUM", "HARD" }

-- playerHandle -> { easy=, medium=, hard=, onSelect= }
local pendingSelections = {}

local function trim(s)
  return s:match("^%s*(.-)%s*$")
end

local function splitSynonyms(entry)
  local names = {}
  for name in entry:gmatch("[^,]+") do
    names[#names + 1] = trim(name)
  end
  return names
end

local function getRandomTheme(session, difficulty, playedThemes)
  local themes = session.config.getStringList("themes." .. difficulty:lower())
  if #themes == 0 then
    themes = { "House" }
  end

  local available = {}
  for _, candidate in ipairs(themes) do
    local alreadyPlayed = false
    for _, played in ipairs(playedThemes) do
      if played == candidate then
        alreadyPlayed = true
        break
      end
    end
    if not alreadyPlayed then
      available[#available + 1] = candidate
    end
  end
  if #available == 0 then
    available = themes
  end

  local selected = available[math.random(#available)]
  return { names = splitSynonyms(selected), difficulty = difficulty }
end

function M.getRandomTheme(session, difficulty, playedThemes)
  return getRandomTheme(session, difficulty, playedThemes)
end

function M.forceRandomTheme(session, playedThemes)
  local difficulty = DIFFICULTIES[math.random(#DIFFICULTIES)]
  return getRandomTheme(session, difficulty, playedThemes)
end

local function buildItemDefinition(session, builderHandle, theme, labelKey)
  local label = session.config.translation(builderHandle, labelKey) or theme.difficulty
  local points = tostring(DIFFICULTY_POINTS[theme.difficulty])
  local name = label:gsub("{theme}", theme.names[1]):gsub("{points}", points)

  local lore = { "<gray>" .. table.concat(theme.names, ", ") .. "</gray>", "" }
  local pointsLore = session.config.translation(builderHandle, "theme_selection.points_lore")
  if pointsLore then
    lore[#lore + 1] = pointsLore:gsub("{points}", points)
  end

  -- The "MODULE;" prefix is stripped by Core's MenuActionExecutor before ba.menu.onAction sees the
  -- payload - matches legacy GuessTheBuildModule's own item action strings.
  return {
    material = "PAPER",
    amount = 1,
    name = name,
    lore = lore,
    actions = { "MODULE;guess_the_build;theme " .. theme.difficulty:lower() },
  }
end

function M.openThemeSelectionMenu(session, builderHandle, playedThemes, onSelect)
  if not builderHandle or not session.player.isOnline(builderHandle) then
    return
  end

  local easy = getRandomTheme(session, "EASY", playedThemes)
  local medium = getRandomTheme(session, "MEDIUM", playedThemes)
  local hard = getRandomTheme(session, "HARD", playedThemes)

  pendingSelections[builderHandle] = { easy = easy, medium = medium, hard = hard, onSelect = onSelect }

  local title = session.config.translation(builderHandle, "theme_selection.menu.title")
    or "<bold><gradient:aqua:light_purple>Select a Theme</gradient></bold>"

  local items = {}
  local easyItem = buildItemDefinition(session, builderHandle, easy, "theme_selection.easy")
  easyItem.slot = 11
  local mediumItem = buildItemDefinition(session, builderHandle, medium, "theme_selection.medium")
  mediumItem.slot = 13
  local hardItem = buildItemDefinition(session, builderHandle, hard, "theme_selection.hard")
  hardItem.slot = 15
  items[#items + 1] = easyItem
  items[#items + 1] = mediumItem
  items[#items + 1] = hardItem

  for i = 0, 26 do
    if i ~= 11 and i ~= 13 and i ~= 15 then
      items[#items + 1] = { slot = i, material = "GRAY_STAINED_GLASS_PANE", amount = 1, name = " ", lore = {}, actions = {} }
    end
  end

  session.menu.open(builderHandle, title, 27, items, {})
end

function M.handleThemeAction(playerHandle, action)
  if not action or action == "" then
    return false
  end
  local diffStr = action:lower()
  local pending = pendingSelections[playerHandle]
  pendingSelections[playerHandle] = nil
  if not pending then
    return false
  end

  local selected
  if diffStr == "easy" then
    selected = pending.easy
  elseif diffStr == "medium" then
    selected = pending.medium
  elseif diffStr == "hard" then
    selected = pending.hard
  end
  if not selected then
    return false
  end

  if pending.onSelect then
    pending.onSelect(selected)
  end
  return true
end

function M.clearPendingSelection(playerHandle)
  if not playerHandle then
    pendingSelections = {}
    return
  end
  pendingSelections[playerHandle] = nil
end

return M

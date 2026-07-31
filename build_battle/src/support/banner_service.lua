-- Mirrors legacy BannerCreatorService.java + BannerBuilderState.java + BannerPatternUtil.java. Menu
-- built directly in Lua (see options_service.lua's own doc comment - BannerMenuHolder.java isn't
-- ported). Unlike legacy's own live-composited preview (each menu icon shows the banner-so-far with
-- the candidate pattern already applied), menu icons here just show a plain banner of the relevant
-- color with the pattern/color name in the label - MenuBinding's own item table has no path for
-- arbitrary ItemMeta injection (JavaItemDefinition only carries material/amount/name/lore/
-- skullValue, and extending it lives in the versioned BlueArcade-API submodule, out of scope for a
-- cosmetic preview) - a documented, deliberate simplification. The real composited banner is still
-- built correctly server-side by BannerItemFactory when the player actually creates it.
-- Per-player builder state (base color + chosen pattern layers) lives in session.state.
-- bannerBuilder[handle], reset every time "options banner" is opened fresh, same convention as
-- state.floorChangeMode/pendingBiomeMenu elsewhere in this module.
local DYE_COLORS = {
  "WHITE", "ORANGE", "MAGENTA", "LIGHT_BLUE", "YELLOW", "LIME", "PINK", "GRAY",
  "LIGHT_GRAY", "CYAN", "PURPLE", "BLUE", "BROWN", "GREEN", "RED", "BLACK",
}

-- Matches BannerPatternUtil.KNOWN_PATTERN_NAMES, minus "BASE" (never offered as a layer).
local PATTERN_NAMES = {
  "BORDER", "BRICKS", "CIRCLE", "CIRCLE_MIDDLE", "CREEPER", "CROSS",
  "CURLY_BORDER", "DIAGONAL_LEFT", "DIAGONAL_RIGHT", "DIAGONAL_LEFT_MIRROR",
  "DIAGONAL_RIGHT_MIRROR", "DIAGONAL_UP_LEFT", "DIAGONAL_UP_RIGHT", "FLOW",
  "FLOWER", "GLOBE", "GRADIENT", "GRADIENT_UP", "GUSTER", "HALF_HORIZONTAL",
  "HALF_HORIZONTAL_BOTTOM", "HALF_HORIZONTAL_MIRROR", "HALF_VERTICAL",
  "HALF_VERTICAL_MIRROR", "HALF_VERTICAL_RIGHT", "MOJANG", "PIGLIN", "RHOMBUS",
  "RHOMBUS_MIDDLE", "SKULL", "SMALL_STRIPES", "SQUARE_BOTTOM_LEFT",
  "SQUARE_BOTTOM_RIGHT", "SQUARE_TOP_LEFT", "SQUARE_TOP_RIGHT", "STRAIGHT_CROSS",
  "STRIPE_BOTTOM", "STRIPE_CENTER", "STRIPE_DOWNLEFT", "STRIPE_DOWNRIGHT",
  "STRIPE_LEFT", "STRIPE_MIDDLE", "STRIPE_RIGHT", "STRIPE_SMALL", "STRIPE_TOP",
  "TRIANGLE_BOTTOM", "TRIANGLE_TOP", "TRIANGLES_BOTTOM", "TRIANGLES_TOP",
}

local BACK_SLOT = 45
local CREATE_SLOT = 49

local M = {}

local function sendMessage(session, handle, path)
  local message = session.config.translation(handle, path)
  if message then
    session.messages.sendRaw(handle, message)
  end
end

local function formatEnumName(value)
  local words = {}
  for part in value:lower():gmatch("[^_]+") do
    words[#words + 1] = part:sub(1, 1):upper() .. part:sub(2)
  end
  return table.concat(words, " ")
end

local function contrastColor(baseColor)
  local white = { BLACK = true, BLUE = true, BROWN = true, CYAN = true, GRAY = true, GREEN = true,
    LIGHT_BLUE = true, MAGENTA = true, ORANGE = true, PINK = true, PURPLE = true, RED = true, YELLOW = true }
  if baseColor and white[baseColor] then
    return "WHITE"
  end
  return "BLACK"
end

local function getBuilder(session, handle)
  local builder = session.state.bannerBuilder[handle]
  if not builder then
    builder = { baseColor = nil, layers = {}, pendingPattern = nil }
    session.state.bannerBuilder[handle] = builder
  end
  return builder
end

local function backItem(session, handle, action)
  return {
    slot = BACK_SLOT, material = "ARROW", amount = 1,
    name = session.config.translation(handle, "options.banner.back") or "Back", lore = {},
    actions = { action },
  }
end

local function createItem(session, handle, builder)
  return {
    slot = CREATE_SLOT, material = builder.baseColor and (builder.baseColor .. "_BANNER") or "WHITE_BANNER", amount = 1,
    name = session.config.translation(handle, "options.banner.create") or "Create Banner",
    lore = { "<gray>Click to add this banner to your inventory.</gray>" },
    actions = { "MODULE;build_battle;options banner create" },
  }
end

function M.openBaseColorMenu(session, handle)
  session.state.bannerBuilder[handle] = { baseColor = nil, layers = {}, pendingPattern = nil }
  local builder = session.state.bannerBuilder[handle]

  local items = {}
  for i, color in ipairs(DYE_COLORS) do
    items[#items + 1] = {
      slot = i - 1, material = color .. "_BANNER", amount = 1, name = "<light_purple>" .. formatEnumName(color), lore = {},
      actions = { "MODULE;build_battle;options banner color " .. color },
    }
  end
  items[#items + 1] = backItem(session, handle, "MODULE;build_battle;options menu main")
  items[#items + 1] = createItem(session, handle, builder)

  local title = session.config.translation(handle, "options.banner.color_title") or "Banner Color"
  session.menu.open(handle, title, 54, items, {})
end

function M.openLayerMenu(session, handle)
  local builder = getBuilder(session, handle)
  local items = {}
  for i, pattern in ipairs(PATTERN_NAMES) do
    items[#items + 1] = {
      slot = i - 1, material = (builder.baseColor or "WHITE") .. "_BANNER", amount = 1,
      name = "<white>" .. formatEnumName(pattern), lore = { "<gray>Click to add this pattern.</gray>" },
      actions = { "MODULE;build_battle;options banner pattern " .. pattern },
    }
  end
  items[#items + 1] = backItem(session, handle, "MODULE;build_battle;options banner")
  items[#items + 1] = createItem(session, handle, builder)

  local title = session.config.translation(handle, "options.banner.layer_title") or "Banner Pattern"
  session.menu.open(handle, title, 54, items, {})
end

function M.openLayerColorMenu(session, handle)
  local builder = getBuilder(session, handle)
  local items = {}
  for i, color in ipairs(DYE_COLORS) do
    items[#items + 1] = {
      slot = i - 1, material = color .. "_BANNER", amount = 1, name = "<light_purple>" .. formatEnumName(color),
      lore = { "<gray>Click to use this color.</gray>" },
      actions = { "MODULE;build_battle;options banner pattern_color " .. color },
    }
  end
  items[#items + 1] = backItem(session, handle, "MODULE;build_battle;options banner")
  items[#items + 1] = createItem(session, handle, builder)

  local title = session.config.translation(handle, "options.banner.layer_color_title") or "Pattern Color"
  session.menu.open(handle, title, 54, items, {})
end

local function selectBaseColor(session, handle, color)
  local builder = getBuilder(session, handle)
  builder.baseColor = color
  builder.layers = {}
  M.openLayerMenu(session, handle)
end

local function selectPattern(session, handle, pattern)
  local builder = getBuilder(session, handle)
  builder.pendingPattern = pattern
  M.openLayerColorMenu(session, handle)
end

local function selectPatternColor(session, handle, color)
  local builder = getBuilder(session, handle)
  if builder.pendingPattern then
    builder.layers[#builder.layers + 1] = { color = color, pattern = builder.pendingPattern }
    builder.pendingPattern = nil
  end
  M.openLayerMenu(session, handle)
end

local function createFinalBanner(session, handle)
  local builder = getBuilder(session, handle)
  local name = session.config.translation(handle, "options.banner.final_name")
  session.player.giveBannerItem(handle, -1, builder.baseColor, builder.layers, name)
  sendMessage(session, handle, "options.messages.banner_created")
  session.state.bannerBuilder[handle] = nil
end

-- args[1] is always "banner". args[2] nil (bare "options banner") re-enters the wizard from the
-- top, matching legacy's own OptionsService.handleModuleAction "banner" case.
function M.handleModuleAction(session, handle, args)
  local action = args[2] and args[2]:lower()
  if not action then
    M.openBaseColorMenu(session, handle)
    return true
  elseif action == "color" and args[3] then
    selectBaseColor(session, handle, args[3]:upper())
    return true
  elseif action == "pattern" and args[3] then
    selectPattern(session, handle, args[3]:upper())
    return true
  elseif action == "pattern_color" and args[3] then
    selectPatternColor(session, handle, args[3]:upper())
    return true
  elseif action == "create" then
    createFinalBanner(session, handle)
    return true
  end
  return false
end

return M

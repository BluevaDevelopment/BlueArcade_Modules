-- Mirrors legacy HeadsService.java + SkullUtil.java. The categories/heads menus are built directly
-- in Lua via session.menu.open's existing skullValue item field (already end-to-end wired for real
-- Base64 skull textures - see MenuItemBuilder.kt's own net.blueva.foundation.items.Items.skullValue
-- call) - no new binding needed for the menu icons themselves. "Click to add this head" instead
-- gives a real skull item via the new PlayerBinding.giveSkullItem (a thin wrapper around that same
-- Items.skullValue helper). openSearchMenu isn't ported - legacy's own OptionsService.
-- handleModuleAction switch never exposes a "search" action, so it's unreachable through the real
-- click-driven UI (a genuinely dead path from this angle, not a fabricated skip).
local BACK_SLOT = 45

local CATEGORIES = {
  {
    id = "mobs", name = "<red>Mobs", icon = "ZOMBIE_HEAD",
    heads = {
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvZjQyNTQ4MzhjMzNlYTIyN2ZmY2EyMjNkZGRhYWJmZTBiMDIxNWY3MGRhNjQ5ZTk0NDQ3N2Y0NDM3MGNhNjk1MiJ9fX0=", name = "<green>Creeper" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvNTZmYzg1NGJiODRjZjRiNzY5NzI5Nzk3M2UwMmI3OWJjMTA2OTg0NjBiNTFhNjM5YzYwZTVlNDE3NzM0ZTExIn19fQ==", name = "<dark_green>Zombie" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvMzAxMjY4ZTljNDkyZGExZjBkODgyNzFjYjQ5MmE0YjMwMjM5NWY1MTVhN2JiZjc3ZjRhMjBiOTVmYzAyZWIyIn19fQ==", name = "<gray>Skeleton" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvN2E1OWJiMGE3YTMyOTY1YjNkOTBkOGVhZmE4OTlkMTgzNWY0MjQ1MDllYWRkNGU2YjcwOWFkYTUwYjljZiJ9fX0=", name = "<dark_purple>Enderman" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvY2RmNzRlMzIzZWQ0MTQzNjk2NWY1YzU3ZGRmMjgxNWQ1MzMyZmU5OTllNjhmYmI5ZDZjZjVjOGJkNDEzOWYifX19", name = "<dark_gray>Wither" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvNzk1M2I2YzY4NDQ4ZTdlNmI2YmY4ZmIyNzNkNzIwM2FjZDhlMWJlMTllODE0ODFlYWQ1MWY0NWRlNTlhOCJ9fX0=", name = "<dark_gray>Wither Skeleton" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvYjc4ZWYyZTRjZjJjNDFhMmQxNGJmZGU5Y2FmZjEwMjE5ZjViMWJmNWIzNWE0OWViNTFjNjQ2Nzg4MmNiNWYwIn19fQ==", name = "<gold>Blaze" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvNzRlOWM2ZTk4NTgyZmZkOGZmOGZlYjMzMjJjZDE4NDljNDNmYjE2YjE1OGFiYjExY2E3YjQyZWRhNzc0M2ViIn19fQ==", name = "<pink>Zombified Piglin" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvZGRlZGJlZTQyYmU0NzJlM2ViNzkxZTdkYmRmYWYxOGM4ZmU1OTNjNjM4YmExMzk2YzllZjY4ZjU1NWNiY2UifX19", name = "<dark_purple>Witch" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvODkwOTFkNzllYTBmNTllZjdlZjk0ZDdiYmE2ZTVmMTdmMmY3ZDQ1NzJjNDRmOTBmNzZjNDgxOWE3MTQifX19", name = "<white>Iron Golem" },
    },
  },
  {
    id = "animals", name = "<yellow>Animals", icon = "PORKCHOP",
    heads = {
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvNjIxNjY4ZWY3Y2I3OWRkOWMyMmNlM2QxZjNmNGNiNmUyNTU5ODkzYjZkZjRhNDY5NTE0ZTY2N2MxNmFhNCJ9fX0=", name = "<light_purple>Pig" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvNWQ2YzZlZGE5NDJmN2Y1ZjcxYzMxNjFjNzMwNmY0YWVkMzA3ZDgyODk1ZjlkMmIwN2FiNDUyNTcxOGVkYzUifX19", name = "<white>Cow" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvMTYzODQ2OWE1OTljZWVmNzIwNzUzNzYwMzI0OGE5YWIxMWZmNTkxZmQzNzhiZWE0NzM1YjM0NmE3ZmFlODkzIn19fQ==", name = "<yellow>Chicken" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvNjlkMWQzMTEzZWM0M2FjMjk2MWRkNTlmMjgxNzVmYjQ3MTg4NzNjNmM0NDhkZmNhODcyMjMxN2Q2NyJ9fX0=", name = "<gray>Wolf" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvNTY1N2NkNWMyOTg5ZmY5NzU3MGZlYzRkZGNkYzY5MjZhNjhhMzM5MzI1MGMxYmUxZjBiMTE0YTFkYjEifX19", name = "<yellow>Ocelot" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvZjMxZjljY2M2YjNlMzJlY2YxM2I4YTExYWMyOWNkMzNkMThjOTVmYzczZGI4YTY2YzVkNjU3Y2NiOGJlNzAifX19", name = "<white>Sheep" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvMDE0MzNiZTI0MjM2NmFmMTI2ZGE0MzRiODczNWRmMWViNWIzY2IyY2VkZTM5MTQ1OTc0ZTljNDgzNjA3YmFjIn19fQ==", name = "<blue>Squid" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvODIyZDhlNzUxYzhmMmZkNGM4OTQyYzQ0YmRiMmY1Y2E0ZDhhZThlNTc1ZWQzZWIzNGMxOGE4NmU5M2IifX19", name = "<aqua>Villager" },
    },
  },
  {
    id = "blocks", name = "<gold>Blocks", icon = "GRASS_BLOCK",
    heads = {
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvZGU5YjhhYWU3ZjljYzc2ZDYyNWNjYjhhYmM2ODZmMzBkMzhmOWU2YzQyNTMzMDk4YjlhZDU3N2Y5MWMzMzNjIn19fQ==", name = "<gray>Stone" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvMWFiNDNiOGMzZDM0ZjEyNWU1YTNmOGI5MmNkNDNkZmQxNGM2MjQwMmMzMzI5ODQ2MWQ0ZDRkN2NlMmQzYWVhIn19fQ==", name = "<gold>Dirt" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvMTk1NTM0ZTAyYzU5YjMzZWNlNTYxOTI4MDMzMTk3OTc3N2UwMjVmYTVmYTgxYWU3NWU5OWZkOGVmZGViYjgifX19", name = "<gray>Cobblestone" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvNDNjNzQxNDlkYmM0MTM0ZDhiNWUzYmJlMjk5N2JhMzZhOGE4MDJlMWFmOTI5NThhNDkzYjczNmYxZjQ2OGM4In19fQ==", name = "<gold>Oak Log" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvNDM3ZGJjNzE5MWJmYzM5YTQ1MDRlMmZhODkwYjAyNTlmNTFjMDY0ODIyMWVlZTliNDdmNGRhMmIzZDA1ZjIxIn19fQ==", name = "<green>Leaves" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvMzhjOWE3MzAyNjljZTFkZTNlOWZhMDY0YWZiMzcwY2JjZDA3NjZkNzI5ZjNlMjllNGYzMjBhNDMzYjA5OGI1In19fQ==", name = "<green>Cactus" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvYzNmZWQ1MTRjM2UyMzhjYTdhYzFjOTRiODk3ZmY2NzExYjFkYmU1MDE3NGFmYzIzNWM4ZjgwZDAyOSJ9fX0=", name = "<green>Melon" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvYzAxNDYxOTczNjM0NTI1MTk2ZWNjNzU3NjkzYjE3MWFkYTRlZjI0YWE5MjgzNmY0MmVhMTFiZDc5YzNhNTAyZCJ9fX0=", name = "<aqua>Diamond Block" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvYjZkMWNlNjk3ZTlkYmFhNGNjZjY0MjUxNmFhYTU5ODEzMzJkYWMxZDMzMWFmZWUyZWUzZGNjODllZmRlZGIifX19", name = "<yellow>Gold Block" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvYmJhODQ1OTE0NWQ4M2ZmYzQ0YWQ1OGMzMjYwZTc0Y2E1YTBmNjM0YzdlZWI1OWExYWQzMjM0ODQ5YzkzM2MifX19", name = "<white>Iron Block" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvNzI4YTE4MTU2ODlkNzE5NGNmN2RiMDYxYjU5ZjYzMTA2MjY0YjUxMzg3OTc2YTdmYjc0YWI3OWI1NjQxIn19fQ==", name = "<red>TNT" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvZDkzNmE0YjZhYjM1OGVmM2YxYjljYmNkOTljYTYyZGM3ODc3ZDIxZWQ1NjQ3ZDhjNzBkOTY0OTA5ZjU3Y2EifX19", name = "<dark_purple>Obsidian" },
    },
  },
  {
    id = "misc", name = "<light_purple>Misc", icon = "PLAYER_HEAD",
    heads = {
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvYmFkYzA0OGE3Y2U3OGY3ZGFkNzJhMDdkYTI3ZDg1YzA5MTY4ODFlNTUyMmVlZWQxZTNkYWYyMTdhMzhjMWEifX19", name = "<green>Question Mark" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvMzA0MGZlODM2YTZjMmZiZDJjN2E5YzhlYzZiZTUxNzRmZGRmMWFjMjBmNTVlMzY2MTU2ZmE1ZjcxMmUxMCJ9fX0=", name = "<green>Arrow Up" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvNzQzNzM0NmQ4YmRhNzhkNTI1ZDE5ZjU0MGE5NWU0ZTc5ZGFlZGE3OTVjYmM1YTEzMjU2MjM2MzEyY2YifX19", name = "<red>Arrow Down" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvYmQ2OWUwNmU1ZGFkZmQ4NGU1ZjNkMWMyMTA2M2YyNTUzYjJmYTk0NWVlMWQ0ZDcxNTJmZGM1NDI1YmMxMmE5In19fQ==", name = "<yellow>Arrow Left" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvMTliZjMyOTJlMTI2YTEwNWI1NGViYTcxM2FhMWIxNTJkNTQxYTFkODkzODgyOWM1NjM2NGQxNzhlZDIyYmYifX19", name = "<yellow>Arrow Right" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvNGUzY2E1YjM5MGQxZTVmMjk3MjgzMjU3Y2U5MGFjNmY4NzgzZDc4NmVjYWVlMDk1YjQ5Y2M2Yjk0NGQ3MmQifX19", name = "<yellow>Hay Bale" },
      { texture = "eyJ0ZXh0dXhlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvMWFmZjkzZWJlY2MxZjhmYmQxM2JhNzgzOWVjN2JkY2RlY2FiN2MwN2ZkOGJhNzhlZTc4YWQwYmQzYWNjYmUifX19", name = "<red>Redstone Lamp" },
      { texture = "eyJ0ZXh0dXJlcyI6eyJTS0lOIjp7InVybCI6Imh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvN2ViNGM0MWY0ODFlODE2Y2Y0YjUwN2IwYTE3NTk1ZjJiYTFmMjQ2NjRkYzQzMmJlMzQ3ZDRlN2E0ZWIzIn19fQ==", name = "<light_purple>Mycelium" },
    },
  },
}

local M = {}

local function findCategory(id)
  if not id then return nil end
  for _, cat in ipairs(CATEGORIES) do
    if cat.id:lower() == id:lower() then
      return cat
    end
  end
  return nil
end

function M.openCategoriesMenu(session, handle)
  local items = {}
  for i, cat in ipairs(CATEGORIES) do
    items[#items + 1] = {
      slot = i - 1,
      material = cat.icon,
      amount = 1,
      name = cat.name,
      lore = {},
      actions = { "MODULE;build_battle;options heads category " .. cat.id },
    }
  end
  items[#items + 1] = {
    slot = BACK_SLOT,
    material = "ARROW",
    amount = 1,
    name = session.config.translation(handle, "options.banner.back") or "Back",
    lore = {},
    actions = { "MODULE;build_battle;options menu main" },
  }
  local title = session.config.translation(handle, "options.heads.title") or "Player Heads"
  session.menu.open(handle, title, 54, items, {})
end

function M.openHeadsMenu(session, handle, categoryId)
  local category = findCategory(categoryId)
  if not category then
    return
  end
  local items = {}
  for i, head in ipairs(category.heads) do
    items[#items + 1] = {
      slot = i - 1,
      material = "PLAYER_HEAD",
      amount = 1,
      name = head.name,
      lore = {},
      skullValue = head.texture,
      actions = { "MODULE;build_battle;options heads take " .. categoryId .. " " .. (i - 1) },
    }
  end
  items[#items + 1] = {
    slot = BACK_SLOT,
    material = "ARROW",
    amount = 1,
    name = session.config.translation(handle, "options.banner.back") or "Back",
    lore = {},
    actions = { "MODULE;build_battle;options heads menu" },
  }
  local titleTemplate = session.config.translation(handle, "options.heads.category_title") or "{category}"
  session.menu.open(handle, titleTemplate:gsub("{category}", category.name), 54, items, {})
end

function M.takeHead(session, handle, categoryId, index)
  local category = findCategory(categoryId)
  if not category then
    return
  end
  local head = category.heads[index + 1]
  if not head then
    return
  end
  session.player.giveSkullItem(handle, -1, head.texture, head.name)
end

-- args[1] is always "heads" (dispatched by options_service.handleModuleAction) - args[2] is the
-- sub-action.
function M.handleModuleAction(session, handle, args)
  local action = args[2] and args[2]:lower()
  if action == "menu" then
    M.openCategoriesMenu(session, handle)
    return true
  elseif action == "category" then
    M.openHeadsMenu(session, handle, args[3])
    return true
  elseif action == "take" then
    M.takeHead(session, handle, args[3], tonumber(args[4]))
    return true
  end
  return false
end

return M

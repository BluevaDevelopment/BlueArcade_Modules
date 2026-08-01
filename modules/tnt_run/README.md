# BlueArcade - TNT Run

This resource is a **BlueArcade 3 module** and requires the core plugin to run.
Get BlueArcade 3 here: https://blueva.net/store/blue-arcade

## Description
Outrun the collapsing floor to survive. The last player standing wins.

## Game type notes
This is a **Minigame**: it is designed for standalone arenas, but it can also be used inside party rotations. Minigames usually provide longer, feature-rich rounds.

## What you get with BlueArcade 3 + this module
- Party system (lobbies, queues, and shared party flow).
- Store-ready menu integration and vote menus.
- Victory effects and end-game celebrations.
- Scoreboards, timers, and game lifecycle management.
- Player stats tracking and placeholders.
- XP system, leaderboards, and achievements.
- Arena management tools and setup commands.

## Features
- Multi-floor support with per-floor removal timing.
- Double-jump configuration.
- Great for vertical, layered arenas.

## Arena setup
### Common steps
Use these steps to register the arena and attach the module:

- `/baa create <id> <standalone|party>` — Create a new arena in standalone or party mode.
- `/baa arena <id> setname <name>` — Give the arena a friendly display name.
- `/baa arena <id> setlobby` — Set the lobby spawn for the arena.
- `/baa arena <id> minplayers <amount>` — Define the minimum players required to start.
- `/baa arena <id> maxplayers <amount>` — Define the maximum players allowed.
- `/baa game <id> add mini tnt_run` — Attach this minigame module to the arena.
- `/baa stick` — Get the setup tool to select regions.
- `/baa game <id> tnt_run bounds set` — Save the game bounds for this arena.
- `/baa game <id> tnt_run spawn add` — Add spawn points for players.
- `/baa game <id> tnt_run time <minutes>` — Set the match duration.

### Module-specific steps
Finish the setup with the commands below:
- `/baa game <id> tnt_run floor add` — Add a new floor using your selection.
- `/baa game <id> tnt_run floor remove <number>` — Remove a configured floor.
- `/baa game <id> tnt_run floor list` — List configured floors.
- `/baa game <id> tnt_run floor delay <ticks>` — Set the block removal delay.
- `/baa game <id> tnt_run floor removal <floor_num> <seconds>` — Set removal time per floor.
- `/baa game <id> tnt_run doublejump set <amount>` — Set the available double jumps.
- `/baa game <id> tnt_run doublejump setboost <vertical|horizontal> <value>` — Tune double jump boost.

## Technical details
- **Minigame ID:** `tnt_run`
- **Module Type:** `MINIGAME`
- **Version:** `1.0.0`

## Links & Support
- Website: https://www.blueva.net
- Documentation: https://docs.blueva.net/books/blue-arcade
- Support: https://discord.com/invite/CRFJ32NdcK

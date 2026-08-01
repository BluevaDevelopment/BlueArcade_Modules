# BlueArcade - Run From The Beast

This resource is a **BlueArcade 3 module** and requires the core plugin to run.
Get BlueArcade 3 here: https://blueva.net/store/blue-arcade

## Description
Escape the Beast, gear up from chests, and fight back together.

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
- Beast spawn point and beast zone setup.
- Loot-driven pacing from arena chests.
- Asymmetrical hunter vs. runners gameplay.

## Arena setup
### Common steps
Use these steps to register the arena and attach the module:

- `/baa create <id> <standalone|party>` — Create a new arena in standalone or party mode.
- `/baa arena <id> setname <name>` — Give the arena a friendly display name.
- `/baa arena <id> setlobby` — Set the lobby spawn for the arena.
- `/baa arena <id> minplayers <amount>` — Define the minimum players required to start.
- `/baa arena <id> maxplayers <amount>` — Define the maximum players allowed.
- `/baa game <id> add mini run_from_the_beast` — Attach this module to the arena.
- `/baa stick` — Get the setup tool to select regions.
- `/baa game <id> run_from_the_beast bounds set` — Save the game bounds for this arena.
- `/baa game <id> run_from_the_beast spawn add` — Add spawn points for players.
- `/baa game <id> run_from_the_beast time <minutes>` — Set the match duration.

### Module-specific steps
Finish the setup with the commands below:
- `/baa game <id> run_from_the_beast beastspawn set` — Set the Beast spawn point.
- `/baa game <id> run_from_the_beast beastzone set` — Select and save the Beast zone.

## Technical details
- **Minigame ID:** `run_from_the_beast`
- **Version:** `1.0.0`
- **Module Type:** `MINIGAME`

## Links & Support
- Website: https://www.blueva.net
- Documentation: https://docs.blueva.net/books/blue-arcade
- Support: https://discord.com/invite/CRFJ32NdcK

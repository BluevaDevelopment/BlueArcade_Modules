# BlueArcade - Red Alert

This resource is a **BlueArcade 3 module** and requires the core plugin to run.
Get BlueArcade 3 here: https://blueva.net/store/blue-arcade

## Description
Survive as the floor heats up beneath you. React quickly and keep moving.

## Game type notes
This is a **Microgame**: it is designed for party game rotations, but it can also run as a standalone arena. Microgames typically focus on short, fast rounds.

## What you get with BlueArcade 3 + this module
- Party system (lobbies, queues, and shared party flow).
- Store-ready menu integration and vote menus.
- Victory effects and end-game celebrations.
- Scoreboards, timers, and game lifecycle management.
- Player stats tracking and placeholders.
- XP system, leaderboards, and achievements.
- Arena management tools and setup commands.

## Features
- Two modes: chaos and trail.
- Floor region setup with the selection tool.
- Intense survival-focused rounds.

## Arena setup
### Common steps
Use these steps to register the arena and attach the module:

- `/baa create <id> <standalone|party>` — Create a new arena in standalone or party mode.
- `/baa arena <id> setname <name>` — Give the arena a friendly display name.
- `/baa arena <id> setlobby` — Set the lobby spawn for the arena.
- `/baa arena <id> minplayers <amount>` — Define the minimum players required to start.
- `/baa arena <id> maxplayers <amount>` — Define the maximum players allowed.
- `/baa game <id> add micro red_alert` — Attach this module to the arena.
- `/baa stick` — Get the setup tool to select regions.
- `/baa game <id> red_alert bounds set` — Save the game bounds for this arena.
- `/baa game <id> red_alert spawn add` — Add spawn points for players.
- `/baa game <id> red_alert time <minutes>` — Set the match duration.

### Module-specific steps
Finish the setup with the commands below:
- `/baa game <id> red_alert floor set` — Select and save the floor region.
- `/baa game <id> red_alert setmode <chaos|trail>` — Choose the gameplay mode.

## Technical details
- **Microgame ID:** `red_alert`
- **Version:** `1.0.0`
- **Module Type:** `MICROGAME`

## Links & Support
- Website: https://www.blueva.net
- Documentation: https://docs.blueva.net/books/blue-arcade
- Support: https://discord.com/invite/CRFJ32NdcK

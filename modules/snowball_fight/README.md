# BlueArcade - Snowball Fight

This resource is a **BlueArcade 3 module** and requires the core plugin to run.
Get BlueArcade 3 here: https://blueva.net/store/blue-arcade

## Description
Throw snowballs and outlast your opponents in a fast, frosty brawl.

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
- Two victory modes: last standing or most kills.
- Lightweight setup for quick rotation play.
- Great for compact arenas.

## Arena setup
### Common steps
Use these steps to register the arena and attach the module:

- `/baa create <id> <standalone|party>` — Create a new arena in standalone or party mode.
- `/baa arena <id> setname <name>` — Give the arena a friendly display name.
- `/baa arena <id> setlobby` — Set the lobby spawn for the arena.
- `/baa arena <id> minplayers <amount>` — Define the minimum players required to start.
- `/baa arena <id> maxplayers <amount>` — Define the maximum players allowed.
- `/baa game <id> add micro snowball_fight` — Attach this module to the arena.
- `/baa stick` — Get the setup tool to select regions.
- `/baa game <id> snowball_fight bounds set` — Save the game bounds for this arena.
- `/baa game <id> snowball_fight spawn add` — Add spawn points for players.
- `/baa game <id> snowball_fight time <minutes>` — Set the match duration.

### Module-specific steps
Finish the setup with the commands below:
- `/baa game <id> snowball_fight setmode <last_standing|most_kills>` — Choose the win condition.

## Technical details
- **Microgame ID:** `snowball_fight`
- **Version:** `1.0.0`
- **Module Type:** `MICROGAME`

## Links & Support
- Website: https://www.blueva.net
- Documentation: https://docs.blueva.net/books/blue-arcade
- Support: https://discord.com/invite/CRFJ32NdcK

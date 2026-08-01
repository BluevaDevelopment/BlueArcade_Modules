# BlueArcade - TNT Tag

This resource is a **BlueArcade 3 module** and requires the core plugin to run.
Get BlueArcade 3 here: https://blueva.net/store/blue-arcade

## Description
Pass the TNT before it explodes. Survive each round to win.

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
- Dedicated play region setup.
- Round-based TNT holder mechanics.
- Great for fast, social gameplay.

## Arena setup
Use these steps to register the arena and attach the module:

- `/baa create <id> <standalone|party>` — Create a new arena in standalone or party mode.
- `/baa arena <id> setname <name>` — Give the arena a friendly display name.
- `/baa arena <id> setlobby` — Set the lobby spawn for the arena.
- `/baa arena <id> minplayers <amount>` — Define the minimum players required to start.
- `/baa arena <id> maxplayers <amount>` — Define the maximum players allowed.
- `/baa game <id> add mini tnt_tag` — Attach this minigame module to the arena.
- `/baa stick` — Get the setup tool to select regions.
- `/baa game <id> tnt_tag bounds set` — Save the game bounds for this arena.
- `/baa game <id> tnt_tag spawn add` — Add spawn points for players.
- `/baa game <id> tnt_tag time <minutes>` — Set the match duration.

No module-specific setup step is required beyond this: once the bounds and spawn points are set, TNT Tag is ready to play.

## Technical details
- **Minigame ID:** `tnt_tag`
- **Module Type:** `MINIGAME`
- **Version:** `1.0.0`

## Links & Support
- Website: https://www.blueva.net
- Documentation: https://docs.blueva.net/books/blue-arcade
- Support: https://discord.com/invite/CRFJ32NdcK

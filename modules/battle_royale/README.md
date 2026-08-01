# BlueArcade - Battle Royale

This resource is a **BlueArcade 3 module** and requires the core plugin to run.
Get BlueArcade 3 here: https://blueva.net/store/blue-arcade

## Description
Drop in, loot, and survive the storm. Be the last team or player standing.

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
- Team size and team count configuration.
- Storm/zone mechanics for late-game pressure.
- Optional regeneration region for arena cleanup.

## Arena setup
### Common steps
Use these steps to register the arena and attach the module:

- `/baa create <id> <standalone|party>` — Create a new arena in standalone or party mode.
- `/baa arena <id> setname <name>` — Give the arena a friendly display name.
- `/baa arena <id> setlobby` — Set the lobby spawn for the arena.
- `/baa arena <id> minplayers <amount>` — Define the minimum players required to start.
- `/baa arena <id> maxplayers <amount>` — Define the maximum players allowed.
- `/baa game <id> add mini battle_royale` — Attach this minigame module to the arena.
- `/baa stick` — Get the setup tool to select regions.
- `/baa game <id> battle_royale bounds set` — Save the game bounds for this arena.
- ~~`/baa game <id> battle_royale spawn add`~~ — Not used in Battle Royale.
  Players are deployed via the drop mechanic at match start.
- `/baa game <id> battle_royale time <minutes>` — Optional. Set a match time limit; leave unset (or `0`) for no limit, in which case the match ends only when a single team or player remains.

### Module-specific steps
Finish the setup with the commands below:
- `/baa game <id> battle_royale region` — Configure the module-specific region setup data.
- `/baa game <id> battle_royale team` — Configure the module-specific team setup data.

## Technical details
- **Minigame ID:** `battle_royale`
- **Module Type:** `MINIGAME`
- **Version:** `1.0.0`

## Links & Support
- Website: https://www.blueva.net
- Documentation: https://docs.blueva.net/books/blue-arcade
- Support: https://discord.com/invite/CRFJ32NdcK

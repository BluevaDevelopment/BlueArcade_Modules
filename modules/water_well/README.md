# BlueArcade - Water Well

This resource is a **BlueArcade 3 module** and requires the core plugin to run.
Get BlueArcade 3 here: https://blueva.net/store/blue-arcade

## Description
Jump into the water well from above and score points!

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
- Players jump from elevated spawn points into a water well.
- Landing in water: +2 points, water turns into random colored wool.
- Missing water: -1 point.
- Live scoreboard with top players ranked by score.
- Quick rounds with simple rules.

## Arena setup
### Common steps
Use these steps to register the arena and attach the module:

- `/baa create <id> <standalone|party>` — Create a new arena in standalone or party mode.
- `/baa arena <id> setname <name>` — Give the arena a friendly display name.
- `/baa arena <id> setlobby` — Set the lobby spawn for the arena.
- `/baa arena <id> minplayers <amount>` — Define the minimum players required to start.
- `/baa arena <id> maxplayers <amount>` — Define the maximum players allowed.
- `/baa game <id> add micro water_well` — Attach this microgame module to the arena.
- `/baa stick` — Get the setup tool to select regions.
- `/baa game <id> water_well bounds set` — Save the game bounds for this arena.
- `/baa game <id> water_well spawn add` — Add spawn points for players.
- `/baa game <id> water_well time <minutes>` — Set the match duration.

### Module-specific steps
No additional setup is required beyond common steps. Ensure spawn points are elevated above the water well.

> ⚠️ **Important map-design requirement:**
> The `-1` (missed landing) logic is triggered when the player receives **fall damage**.
> Configure your map so jumps into non-water blocks are high enough to cause fall damage in Minecraft.
> As a practical baseline, keep a minimum drop of **4+ blocks** to guarantee fall-damage checks can occur.

## Technical details
- **Microgame ID:** `water_well`
- **Module Type:** `MICROGAME`
- **Version:** `1.0.0`

## Links & Support
- Website: https://www.blueva.net
- Documentation: https://docs.blueva.net/books/blue-arcade
- Support: https://discord.com/invite/CRFJ32NdcK

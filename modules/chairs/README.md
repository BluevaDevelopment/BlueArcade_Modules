# BlueArcade - Chairs

This resource is a **BlueArcade 3 module** and requires the core plugin to run.
Get BlueArcade 3 here: https://blueva.net/store/blue-arcade

## Description
Musical chairs for BlueArcade: music plays, seats appear, and players must sit before the timer ends.
Each round removes players until only one remains.

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
- Random music track each round.
- Configurable sit phase and music phase timings.
- Configurable timing reduction per round.
- Configurable seat entities (minecart, boat, pig, horse, and more).
- Flat seat resolver with optional warmup rounds and a simple `playersAlive - seat_reduction` flow.
- Seats spawn inside arena bounds and drop from above the detected ground.

## Seat flow
- For the first `seats.warmup_rounds`, the game can spawn one seat per alive player.
- If `seats.warmup_max_players` is `0`, those warmup rounds apply to any player count.
- After the warmup, the game always uses `max(seats.minimum_seats, playersAlive - seats.seat_reduction)`.
- With the default values, that means: a couple of test rounds first, then classic musical chairs with one less seat than alive players.

## Arena setup
### Common steps
Use these steps to register the arena and attach the module:

- `/baa create <id> <standalone|party>` — Create a new arena in standalone or party mode.
- `/baa arena <id> setname <name>` — Give the arena a friendly display name.
- `/baa arena <id> setlobby` — Set the lobby spawn for the arena.
- `/baa arena <id> minplayers <amount>` — Define the minimum players required to start.
- `/baa arena <id> maxplayers <amount>` — Define the maximum players allowed.
- `/baa game <id> add micro chairs` — Attach this microgame module to the arena.
- `/baa stick` — Get the setup tool to select regions.
- `/baa game <id> chairs bounds set` — Save the game bounds for this arena.
- `/baa game <id> chairs spawn add` — Add spawn points for players.
- `/baa game <id> chairs time <minutes>` — Set the match duration.

### Module-specific steps
Finish the setup with the commands below:
- `/baa game <id> chairs musictime <seconds>` — Set the initial music phase time for that arena (optional).
- `/baa game <id> chairs sittime <seconds>` — Set the initial sit phase time for that arena (optional).
- `/baa game <id> chairs musicreduction <seconds>` — Set how much music time is reduced each round (optional).
- `/baa game <id> chairs sitreduction <seconds>` — Set how much sit time is reduced each round (optional).

## Technical details
- **Microgame ID:** `chairs`
- **Module Type:** `MICROGAME`
- **Version:** `1.0.0`

## Links & Support
- Website: https://www.blueva.net
- Documentation: https://docs.blueva.net/books/blue-arcade
- Support: https://discord.com/invite/CRFJ32NdcK

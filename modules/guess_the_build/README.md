# BlueArcade - Guess The Build

This resource is a **BlueArcade 3 module** and requires the core plugin to run.
Get BlueArcade 3 here: https://blueva.net/store/blue-arcade

## Description
One player builds a secret theme while the others try to guess it by typing in chat. Rotate builders and compete for the most points!

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
- Builder rotation: each round a random player becomes the builder.
- Theme selection GUI with Easy, Medium, and Hard difficulties.
- Action bar hints: underscores reveal random letters as time passes.
- Chat guessing: exact case-insensitive match against theme synonyms.
- Points for correct guesses (difficulty base + speed bonus).
- Points for the builder every time someone guesses correctly.
- Invisible players between builder and guessers during build time.
- Simplified build options: time, floor, and automatic plot reset between rounds.
- Automatic round rotation with configurable rounds per plot.

## Arena setup
### Common steps
Use these steps to register the arena and attach the module:

- `/baa create <id> <standalone|party>` — Create a new arena in standalone or party mode.
- `/baa arena <id> setname <name>` — Give the arena a friendly display name.
- `/baa arena <id> setlobby` — Set the lobby spawn for the arena.
- `/baa arena <id> minplayers <amount>` — Define the minimum players required to start.
- `/baa arena <id> maxplayers <amount>` — Define the maximum players allowed.
- `/baa game <id> add mini guess_the_build` — Attach this minigame module to the arena.
- `/baa stick` — Get the setup tool to select regions.
- `/baa game <id> guess_the_build bounds set` — Save the game bounds for this arena.
- ~~`/baa game <id> guess_the_build spawn add`~~ — Not used in Guess The Build.
  Use **`/baa game <id> guess_the_build plot set`** to configure plot-based spawns.
- `/baa game <id> guess_the_build time <minutes>` — Set the build duration.

### Module-specific steps
Guess The Build requires **a single shared plot** where all players gather and the current builder constructs.

- `/baa game <id> guess_the_build plot set` — Define the shared build area using the stick selection (select 2 corners first). Your current location is saved as the plot spawn.
- `/baa game <id> guess_the_build plot spawn` — Update the spawn point of the plot to your current location.

The floor material is detected **automatically** from the lowest block layer of your selection.

**Plot requirements:**
- At least **3 blocks high** (1 floor layer + 2 blocks of air for building).
- The **floor must be 1-2 block layers thick**. If more than 2 layers contain blocks, the selection is rejected.

**Example workflow:**
1. `/baa stick` — Get the selection tool.
2. Select corner 1 and corner 2 of the build area (make sure it is at least 3 blocks high).
3. `/baa game 1 guess_the_build plot set` — Save the plot. The floor is auto-detected and your current location is set as the spawn.
4. (Optional) `/baa game 1 guess_the_build plot spawn` — Adjust the spawn point if needed.

## Technical details
- **Minigame ID:** `guess_the_build`
- **Module Type:** `MINIGAME`
- **Version:** `1.0.0`

## Links & Support
- Website: https://www.blueva.net
- Documentation: https://docs.blueva.net/books/blue-arcade
- Support: https://discord.com/invite/CRFJ32NdcK

<p align="center">
  <img src="assets/bluearcade-logo.png" alt="BlueArcade" width="760">
</p>

<h1 align="center">BlueArcade Modules</h1>

<p align="center">
  <strong>Official Universal Modules for BlueArcade 3.</strong>
</p>

<p align="center">
  <img alt="License: GPL v3" src="https://img.shields.io/badge/License-GPLv3-blue.svg">
  <img alt="PRs Welcome" src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg">
  <img alt="BlueArcade 3" src="https://img.shields.io/badge/BlueArcade-3-9146FF.svg">
  <img alt="Format" src="https://img.shields.io/badge/format-.bamodule-orange.svg">
  <img alt="GitHub issues" src="https://img.shields.io/github/issues/BluevaDevelopment/BlueArcade_Modules">
  <img alt="GitHub last commit" src="https://img.shields.io/github/last-commit/BluevaDevelopment/BlueArcade_Modules">
</p>

This repository hosts the source of every Universal Module maintained and published officially by
Blueva for BlueArcade 3. None of them ship bundled with the core plugin. Each one is downloaded for
free from the store instead, on its own. Community and third party modules are not hosted here.
They are built, published, and maintained independently by their own authors, on their own terms.

## What is a .bamodule

A Universal Module (`.bamodule`) is a sandboxed, Lua scripted minigame built for BlueArcade 3. It
runs identically across every BlueArcade Edition, including Minecraft and Hytale, without any
compiling or platform specific code involved. A built `.bamodule` file can simply be dropped into a
running server, with no installation step beyond that.

## Official Modules

Every official module can be browsed at
[blueva.net/store/blue-arcade/modules](https://blueva.net/store/blue-arcade/modules), and
downloaded directly using its module id at `blueva.net/store/blue-arcade/modules/<module_id>`, for
example [blueva.net/store/blue-arcade/modules/block_party](https://blueva.net/store/blue-arcade/modules/block_party).

### Minigames

Longer, full length matches.

| Module | Description | Download |
|---|---|---|
| Battle Royale | Last player standing inside a shrinking world. | [Get it](https://blueva.net/store/blue-arcade/modules/battle_royale) |
| Bed Wars | Protect your bed, break the beds of every other team, then eliminate them for good. | [Get it](https://blueva.net/store/blue-arcade/modules/bed_wars) |
| Block Party | Stand on the color the caller announced before the floor beneath every other color disappears. | [Get it](https://blueva.net/store/blue-arcade/modules/block_party) |
| Bridge Race | Race across a collapsing bridge before it falls apart completely. | [Get it](https://blueva.net/store/blue-arcade/modules/bridge_race) |
| Build Battle | Build the best creation for a given theme within the time limit. | [Get it](https://blueva.net/store/blue-arcade/modules/build_battle) |
| Capture The Wool | Capture the flag, played with wool instead of a flag. | [Get it](https://blueva.net/store/blue-arcade/modules/capture_the_wool) |
| Guess The Build | Guess what another player is building, in real time, before anyone else does. | [Get it](https://blueva.net/store/blue-arcade/modules/guess_the_build) |
| Lucky Pillars | Survive on shrinking pillars while random effects change the rules underneath you. | [Get it](https://blueva.net/store/blue-arcade/modules/lucky_pillars) |
| Run From The Beast | Escape a player controlled monster before it catches up to you. | [Get it](https://blueva.net/store/blue-arcade/modules/run_from_the_beast) |
| SkyWars | Loot floating islands, then fight down to a single winning team. | [Get it](https://blueva.net/store/blue-arcade/modules/skywars) |
| Speed Builders | Recreate the shown structure as fast and as accurately as possible. | [Get it](https://blueva.net/store/blue-arcade/modules/speed_builders) |
| TNT Run | Keep moving. The block beneath your feet disappears the moment you step off it. | [Get it](https://blueva.net/store/blue-arcade/modules/tnt_run) |
| TNT Tag | Tag another player to pass along a live TNT charge before it detonates on you. | [Get it](https://blueva.net/store/blue-arcade/modules/tnt_tag) |

### Microgames

Short, fast paced rounds.

| Module | Description | Download |
|---|---|---|
| All Against All | A pure free for all skirmish, every player for themselves. | [Get it](https://blueva.net/store/blue-arcade/modules/all_against_all) |
| Chairs | Musical chairs. Grab a seat before the music stops or you are out. | [Get it](https://blueva.net/store/blue-arcade/modules/chairs) |
| Exploding Sheep | Herd, dodge, or weaponize sheep that explode on contact. | [Get it](https://blueva.net/store/blue-arcade/modules/exploding_sheep) |
| Fast Zone | Stay inside the shrinking safe zone or take the consequences. | [Get it](https://blueva.net/store/blue-arcade/modules/fast_zone) |
| Knockback | Pure knockback combat, send opponents off the platform to win. | [Get it](https://blueva.net/store/blue-arcade/modules/knockback) |
| Minefield | Cross a field seeded with hidden explosive traps. | [Get it](https://blueva.net/store/blue-arcade/modules/minefield) |
| One In The Chamber | Single arrow duels. Land a hit and you earn another shot. | [Get it](https://blueva.net/store/blue-arcade/modules/one_in_the_chamber) |
| Race | Sprint through an obstacle course to reach the finish line first. | [Get it](https://blueva.net/store/blue-arcade/modules/race) |
| Red Alert | Freeze the instant the alarm sounds, any movement gets you eliminated. | [Get it](https://blueva.net/store/blue-arcade/modules/red_alert) |
| Snowball Fight | Knock opponents off the platform using nothing but snowballs. | [Get it](https://blueva.net/store/blue-arcade/modules/snowball_fight) |
| Spleef | Break the floor beneath your opponents until they fall through. | [Get it](https://blueva.net/store/blue-arcade/modules/spleef) |
| Splegg | Spleef, but the shovel is a TNT launching gun. | [Get it](https://blueva.net/store/blue-arcade/modules/splegg) |
| Traffic Light | Red light, green light. Move only when it is safe to. | [Get it](https://blueva.net/store/blue-arcade/modules/traffic_light) |
| Water Well | Push opponents into the water below to eliminate them. | [Get it](https://blueva.net/store/blue-arcade/modules/water_well) |

## Creating Your Own Modules

Anyone can build a Universal Module using
[`bacli`](https://github.com/BluevaDevelopment/BlueArcade_CLI), the official BlueArcade authoring
CLI, and publish it independently at
[blueva.net/store/blue-arcade/modules/manage](https://blueva.net/store/blue-arcade/modules/manage).
Publishing this way keeps the module yours: you stay in full control of it and you are the one
responsible for maintaining it going forward. Opening a pull request against this repository is not
required to do this.

A pull request here serves a different purpose: submitting a new module so that Blueva publishes
and maintains it officially from that point on, alongside the modules listed above.

## Contributing

Pull requests are welcome, whether that means fixing a bug in an official module, improving one, or
submitting a brand new module for official adoption. Opening an issue first for anything non
trivial is appreciated, so the change can be discussed before any real work goes into it.

## License

Licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for the full text.

## About BlueArcade

Part of [BlueArcade 3](https://blueva.net), a cross platform framework for building modular
multiplayer minigames.

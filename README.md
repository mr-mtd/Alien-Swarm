# Alien Swarm

A 3D hack and slash game built with [Godot 4](https://godotengine.org) and GDScript.

You're stuck in an arena, and waves of aliens keep coming, with more in each wave. Cut them down with a sword combo, dodge their lunges, and see how many waves you can survive.

## Running the game

1. Install [Godot 4.5](https://godotengine.org/download) or newer (the standard build, not .NET).
2. Open Godot, click **Import**, and select this folder's `project.godot`.
3. Press **F5** (or the ▶ button) to play.

## Controls

| Action | Input |
| --- | --- |
| Move | W A S D |
| Look | Mouse |
| Attack (press again mid-swing to combo, up to 3 hits) | Left mouse button |
| Dodge roll (brief invulnerability) | Shift |
| Jump | Space |
| Release / recapture mouse | Esc / click |
| Restart after death | R |

## Project layout

```
project.godot       Project settings, input map, physics layer names
scenes/main.tscn    Arena, lighting, HUD; the scene that runs on launch
scenes/player.tscn  Player body, sword, hitbox, third-person camera
scenes/enemy.tscn   Skitterer, the common alien
scenes/duskmane.tscn  Duskmane, a tough club-wielding alien that rushes in and backs off
scenes/alien_terrain.tscn  The alien world around the arena (built by scripts/alien_terrain.gd)
scripts/main.gd     Wave spawning, game over and restart
scripts/player.gd   Movement, dodge, combo attacks, health
scripts/enemy.gd    Chase, telegraphed attack, stagger, death
scripts/duskmane.gd Rush / hold-off hunting cycle, club attack, heavy poise
scripts/hud.gd      Health bar, wave and kill counters, messages
scripts/alien_terrain.gd  Generates ground, grass, trees, shrubs, rocks, crystals, spores and point lights
shaders/            Sky (nebula, stars, ringed planet), ground, grass and plant shaders
```

Physics layers: 1 = world, 2 = player, 3 = enemies.

The world around the arena is generated from code when the scene loads, so it needs no downloaded assets and works with the GL Compatibility renderer. Select the AlienTerrain node in main.tscn to change its seed, grass density and tree count. None of it has collision; the arena's invisible floor and walls still handle gameplay.
